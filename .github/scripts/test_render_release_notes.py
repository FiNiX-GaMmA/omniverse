#!/usr/bin/env python3

import unittest

from render_release_notes import (
    latest_version,
    notes_for_version,
    render_release_body,
)


SAMPLE = """# Changelog

## 🚀 [v2.1.86] - 2026-07-29

### New fixes
- Current release detail.

---

## 🚀 [v2.1.85] - 2026-07-28

### Older fixes
- Previous release detail.

---
"""


class ReleaseNotesTests(unittest.TestCase):
    def test_latest_version_comes_from_first_versioned_heading(self):
        self.assertEqual(latest_version(SAMPLE), "2.1.86")

    def test_extracts_only_the_requested_version(self):
        notes = notes_for_version(SAMPLE, "v2.1.86")
        self.assertIn("Current release detail", notes)
        self.assertNotIn("Previous release detail", notes)

    def test_missing_version_fails_instead_of_publishing_stale_notes(self):
        with self.assertRaisesRegex(ValueError, "no section for v2.1.87"):
            notes_for_version(SAMPLE, "2.1.87")

    def test_release_body_combines_changelog_and_installation_details(self):
        body = render_release_body(SAMPLE, "2.1.86")
        self.assertIn("# ✨ Omniverse v2.1.86 Release", body)
        self.assertIn("Current release detail", body)
        self.assertIn("Official installation matrix", body)
        self.assertIn("xattr -cr /Applications/Omniverse.app", body)


if __name__ == "__main__":
    unittest.main()
