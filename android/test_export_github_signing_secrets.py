#!/usr/bin/env python3

import base64
import os
from pathlib import Path
import stat
import tempfile
import unittest

import export_github_signing_secrets as signing_export


class SigningSecretsExportTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)
        self.keystore = self.root / "original-release.jks"
        self.keystore.write_bytes(b"existing-release-identity")
        self.properties = self.root / "keystore.properties"
        self.properties.write_text(
            "storeFile=original-release.jks\n"
            "storePassword=store=password\n"
            "keyAlias=omniverse-release\n"
            "keyPassword=key=password\n",
            encoding="utf-8",
        )

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def test_builds_all_four_secrets_from_existing_identity(self) -> None:
        properties = signing_export.parse_properties(self.properties)
        keystore = signing_export.resolve_keystore(self.properties, properties["storeFile"])
        secrets = signing_export.build_secrets(keystore, properties)

        self.assertEqual(
            set(secrets),
            {
                "ANDROID_KEYSTORE_BASE64",
                "ANDROID_KEYSTORE_PASSWORD",
                "ANDROID_KEY_ALIAS",
                "ANDROID_KEY_PASSWORD",
            },
        )
        self.assertEqual(base64.b64decode(secrets["ANDROID_KEYSTORE_BASE64"]), self.keystore.read_bytes())
        self.assertEqual(secrets["ANDROID_KEYSTORE_PASSWORD"], "store=password")
        self.assertEqual(secrets["ANDROID_KEY_PASSWORD"], "key=password")

    def test_private_export_is_0600_and_refuses_an_accidental_overwrite(self) -> None:
        output = self.root / "private" / "github-actions-secrets.env"
        secrets = signing_export.build_secrets(
            self.keystore, signing_export.parse_properties(self.properties)
        )
        signing_export.write_private_export(output, secrets, "abc123", "AA:BB")

        self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o600)
        with self.assertRaises(signing_export.SigningExportError):
            signing_export.write_private_export(output, secrets, "abc123", "AA:BB")

        os.chmod(output, 0o644)
        signing_export.write_private_export(output, secrets, "def456", "CC:DD", force=True)
        self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o600)
        self.assertIn("# Existing keystore SHA-256: def456", output.read_text(encoding="utf-8"))

    def test_normalizes_and_validates_certificate_pin(self) -> None:
        pin = self.root / "release-signing-cert.sha256"
        pin.write_text("aa:" * 31 + "aa\n", encoding="utf-8")
        self.assertEqual(signing_export.read_pinned_certificate(pin), ":".join(["AA"] * 32))

        pin.write_text("not-a-certificate", encoding="utf-8")
        with self.assertRaises(signing_export.SigningExportError):
            signing_export.read_pinned_certificate(pin)

    def test_rejects_missing_and_continued_properties(self) -> None:
        self.properties.write_text("storeFile=original-release.jks\n", encoding="utf-8")
        with self.assertRaises(signing_export.SigningExportError):
            signing_export.parse_properties(self.properties)

        self.properties.write_text(
            "storeFile=original-release.jks\\\n"
            "storePassword=password\nkeyAlias=alias\nkeyPassword=password\n",
            encoding="utf-8",
        )
        with self.assertRaises(signing_export.SigningExportError):
            signing_export.parse_properties(self.properties)

    def test_finds_an_installed_keytool(self) -> None:
        self.assertTrue(Path(signing_export.find_keytool()).is_file())


if __name__ == "__main__":
    unittest.main()
