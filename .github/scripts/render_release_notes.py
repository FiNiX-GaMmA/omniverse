#!/usr/bin/env python3
"""Resolve release metadata and render a GitHub Release body from CHANGELOG.md."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


VERSION_HEADING = re.compile(
    r"^##\s+.*?\[(?P<tag>v?\d+\.\d+\.\d+)\]\s*-\s*.+$",
    re.MULTILINE,
)


def normalized_version(value: str) -> str:
    version = value.strip().lower().removeprefix("v")
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError(f"Invalid semantic version: {value}")
    return version


def changelog_sections(markdown: str) -> list[tuple[str, str]]:
    matches = list(VERSION_HEADING.finditer(markdown))
    sections: list[tuple[str, str]] = []
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(markdown)
        body = markdown[match.end() : end].strip()
        body = re.sub(r"\n?---\s*$", "", body).strip()
        sections.append((normalized_version(match.group("tag")), body))
    return sections


def latest_version(markdown: str) -> str:
    sections = changelog_sections(markdown)
    if not sections:
        raise ValueError("CHANGELOG.md has no versioned release heading")
    return sections[0][0]


def notes_for_version(markdown: str, version: str) -> str:
    requested = normalized_version(version)
    for section_version, notes in changelog_sections(markdown):
        if section_version == requested:
            if not notes:
                raise ValueError(f"CHANGELOG.md section v{requested} is empty")
            return notes
    raise ValueError(f"CHANGELOG.md has no section for v{requested}")


def render_release_body(markdown: str, version: str) -> str:
    clean_version = normalized_version(version)
    notes = notes_for_version(markdown, clean_version)
    return f"""# ✨ Omniverse v{clean_version} Release

> Generated from the matching `CHANGELOG.md` section. Updating that section and rerunning the release workflow updates this page.

---

## 🚀 Changes

{notes}

---

## 📦 Official installation matrix

| Platform | Installer package | Compatibility and instructions |
| :--- | :--- | :--- |
| 🤖 **Android** | `Omniverse-android-arm64.apk` / `Omniverse-android-universal.apk` | Phones, tablets, Android TV, and Fire TV |
| 🍎 **iOS / iPadOS** | `Omniverse-Unsigned.ipa` | Sideload with AltStore, SideStore, TrollStore, or Xcode |
| 💻 **Windows** | `Omniverse Setup *.exe` / portable EXE | Windows 10/11 x64 |
| 🍏 **macOS** | `Omniverse-*.dmg` | Apple Silicon and Intel |
| 🐧 **Linux** | `*.AppImage` / `*.deb` | AppImage and Debian/Ubuntu packages |

> [!IMPORTANT]
> After an in-app macOS update, quit Omniverse and run `xattr -cr /Applications/Omniverse.app` before reopening it.

---

*Published automatically from the versioned changelog by GitHub Actions.*
"""


def main() -> None:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    metadata = subparsers.add_parser("metadata")
    metadata.add_argument("--changelog", default="CHANGELOG.md")
    metadata.add_argument("--github-output")

    render = subparsers.add_parser("render")
    render.add_argument("--changelog", default="CHANGELOG.md")
    render.add_argument("--version", required=True)
    render.add_argument("--output", required=True)

    args = parser.parse_args()
    markdown = Path(args.changelog).read_text(encoding="utf-8")

    if args.command == "metadata":
        version = latest_version(markdown)
        values = f"version={version}\ntag=v{version}\n"
        if args.github_output:
            with Path(args.github_output).open("a", encoding="utf-8") as output:
                output.write(values)
        print(values, end="")
        return

    Path(args.output).write_text(
        render_release_body(markdown, args.version),
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
