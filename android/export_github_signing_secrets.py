#!/usr/bin/env python3
"""Export the existing Android release identity as GitHub Actions secrets.

This helper intentionally cannot create a keystore. Replacing the release key
would prevent users of directly distributed APKs from installing an update over
their existing Omniverse installation.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
from typing import Mapping


REQUIRED_PROPERTIES = ("storeFile", "storePassword", "keyAlias", "keyPassword")
SECRET_NAMES = {
    "storePassword": "ANDROID_KEYSTORE_PASSWORD",
    "keyAlias": "ANDROID_KEY_ALIAS",
    "keyPassword": "ANDROID_KEY_PASSWORD",
}


class SigningExportError(RuntimeError):
    """Raised when the existing signing identity cannot be exported safely."""


def parse_properties(path: Path) -> dict[str, str]:
    """Read the small, flat Java properties file used by the Android build."""
    if not path.is_file():
        raise SigningExportError(
            f"Signing properties were not found at {path}. Restore the original "
            "keystore and properties; do not create a new key for an existing app."
        )

    parsed: dict[str, str] = {}
    for line_number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw_line.strip()
        if not line or line.startswith(("#", "!")):
            continue
        if raw_line.rstrip().endswith("\\"):
            raise SigningExportError(
                f"Unsupported continuation on line {line_number} of {path}."
            )
        key, separator, value = raw_line.partition("=")
        key = key.strip()
        value = value.strip()
        if not separator or not key:
            raise SigningExportError(f"Malformed property on line {line_number} of {path}.")
        if key in parsed:
            raise SigningExportError(f"Duplicate property {key!r} in {path}.")
        if any(character in value for character in ("\r", "\n", "\0")):
            raise SigningExportError(f"Property {key!r} contains an unsafe character.")
        parsed[key] = value

    missing = [key for key in REQUIRED_PROPERTIES if not parsed.get(key)]
    if missing:
        raise SigningExportError(f"Missing required properties: {', '.join(missing)}")
    return parsed


def resolve_keystore(properties_path: Path, store_file: str) -> Path:
    keystore = Path(store_file).expanduser()
    if not keystore.is_absolute():
        keystore = properties_path.parent / keystore
    keystore = keystore.resolve()
    if not keystore.is_file():
        raise SigningExportError(
            f"The original release keystore was not found at {keystore}. "
            "Recover it from a secure backup; generating a replacement breaks update compatibility."
        )
    return keystore


def find_keytool() -> str:
    """Find a real JDK keytool, including unlinked Homebrew installations."""
    candidates: list[Path] = []
    if java_home := os.environ.get("JAVA_HOME"):
        candidates.append(Path(java_home) / "bin" / "keytool")
    candidates.extend(
        Path(path)
        for path in (
            "/opt/homebrew/opt/openjdk@17/bin/keytool",
            "/opt/homebrew/opt/openjdk/bin/keytool",
            "/usr/local/opt/openjdk@17/bin/keytool",
            "/usr/local/opt/openjdk/bin/keytool",
            "/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool",
        )
    )
    if path_keytool := shutil.which("keytool"):
        candidates.append(Path(path_keytool))
    for candidate in candidates:
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    raise SigningExportError("keytool is required. Install or select JDK 17 and try again.")


def certificate_fingerprint(keystore: Path, properties: Mapping[str, str]) -> str:
    """Validate the identity and return its public certificate SHA-256."""
    keytool = find_keytool()

    password_variable = "OMNIVERSE_EXPORT_STORE_PASSWORD"
    environment = os.environ.copy()
    environment[password_variable] = properties["storePassword"]
    result = subprocess.run(
        [
            keytool,
            "-exportcert",
            "-keystore",
            str(keystore),
            "-storepass:env",
            password_variable,
            "-alias",
            properties["keyAlias"],
        ],
        env=environment,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        raise SigningExportError(
            "keytool could not open the keystore with the configured password and alias. "
            "Verify the original signing backup before changing anything."
        )
    digest = hashlib.sha256(result.stdout).hexdigest().upper()
    return ":".join(digest[index : index + 2] for index in range(0, len(digest), 2))


def read_pinned_certificate(path: Path) -> str:
    if not path.is_file():
        raise SigningExportError(f"The signing-certificate pin was not found at {path}.")
    compact = "".join(path.read_text(encoding="utf-8").split()).replace(":", "").upper()
    if len(compact) != 64 or any(character not in "0123456789ABCDEF" for character in compact):
        raise SigningExportError(f"The signing-certificate pin at {path} is malformed.")
    return ":".join(compact[index : index + 2] for index in range(0, len(compact), 2))


def build_secrets(keystore: Path, properties: Mapping[str, str]) -> dict[str, str]:
    secrets = {
        "ANDROID_KEYSTORE_BASE64": base64.b64encode(keystore.read_bytes()).decode("ascii")
    }
    secrets.update({secret: properties[key] for key, secret in SECRET_NAMES.items()})
    return secrets


def write_private_export(
    output_path: Path,
    secrets: Mapping[str, str],
    keystore_fingerprint: str,
    certificate_fingerprint_value: str,
    *,
    force: bool = False,
) -> None:
    output_path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    flags = os.O_WRONLY | os.O_CREAT | (os.O_TRUNC if force else os.O_EXCL)
    try:
        descriptor = os.open(output_path, flags, 0o600)
    except FileExistsError as error:
        raise SigningExportError(
            f"Refusing to overwrite {output_path}; pass --force only after checking the target."
        ) from error

    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as export_file:
            export_file.write("# Omniverse Android signing secrets for GitHub Actions\n")
            export_file.write(f"# Existing keystore SHA-256: {keystore_fingerprint}\n")
            export_file.write(f"# Signing certificate SHA-256: {certificate_fingerprint_value}\n")
            export_file.write("# Never commit or share this file. Delete it after configuring GitHub.\n")
            for name in (
                "ANDROID_KEYSTORE_BASE64",
                "ANDROID_KEYSTORE_PASSWORD",
                "ANDROID_KEY_ALIAS",
                "ANDROID_KEY_PASSWORD",
            ):
                export_file.write(f"{name}={secrets[name]}\n")
    except BaseException:
        try:
            os.close(descriptor)
        except OSError:
            pass
        raise


def build_parser() -> argparse.ArgumentParser:
    repository_root = Path(__file__).resolve().parent.parent
    default_output = Path.home() / ".omniverse" / "signing" / "github-actions-secrets.env"
    parser = argparse.ArgumentParser(
        description="Export the EXISTING Android release key for GitHub Actions (never creates a key)."
    )
    parser.add_argument(
        "--properties",
        type=Path,
        default=repository_root / "android" / "keystore.properties",
        help="Path to the ignored Android signing properties file.",
    )
    parser.add_argument(
        "--certificate-pin",
        type=Path,
        default=repository_root / "android" / "release-signing-cert.sha256",
        help="Versioned SHA-256 pin for the existing app-signing certificate.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=default_output,
        help="Private output file outside the repository.",
    )
    parser.add_argument("--force", action="store_true", help="Replace an existing export file.")
    return parser


def main(argv: list[str] | None = None) -> int:
    arguments = build_parser().parse_args(argv)
    properties_path = arguments.properties.expanduser().resolve()
    output_path = arguments.output.expanduser().resolve()
    try:
        properties = parse_properties(properties_path)
        keystore = resolve_keystore(properties_path, properties["storeFile"])
        actual_certificate = certificate_fingerprint(keystore, properties)
        expected_certificate = read_pinned_certificate(arguments.certificate_pin.expanduser().resolve())
        if actual_certificate != expected_certificate:
            raise SigningExportError(
                "The keystore does not match the pinned Omniverse signing certificate. "
                "Use the original release-key backup; a replacement strands existing users."
            )
        keystore_bytes = keystore.read_bytes()
        keystore_fingerprint = hashlib.sha256(keystore_bytes).hexdigest()
        secrets = build_secrets(keystore, properties)
        write_private_export(
            output_path,
            secrets,
            keystore_fingerprint,
            actual_certificate,
            force=arguments.force,
        )
    except SigningExportError as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1

    source_mode = stat.S_IMODE(keystore.stat().st_mode)
    print("Validated the existing Android release keystore and alias.")
    print(f"Keystore SHA-256: {keystore_fingerprint}")
    print(f"Signing certificate SHA-256: {actual_certificate} (pinned match)")
    print(f"Private GitHub Secrets export: {output_path}")
    print("Export permissions: 0600")
    if source_mode & 0o077:
        print(f"Warning: restrict the source keystore permissions (currently {source_mode:04o}).")
    print("Add all four values under GitHub Settings > Secrets and variables > Actions.")
    print("Then securely delete the export, while retaining the original keystore in a secure backup.")
    print("Do not replace this key: existing direct-install users could no longer update in place.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
