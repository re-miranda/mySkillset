"""Release metadata: SKILL.md and manifest.json must advertise one version."""
from __future__ import annotations

import json
import re
import unittest
from pathlib import Path

SKILL_ROOT = Path(__file__).resolve().parents[2]


class SkillVersionTests(unittest.TestCase):
    def test_skill_metadata_version_equals_manifest_version(self) -> None:
        """Keep the two published versions in sync; e.g. 2.0.5 in both files."""
        manifest = json.loads((SKILL_ROOT / "manifest.json").read_text(encoding="utf-8"))
        text = (SKILL_ROOT / "SKILL.md").read_text(encoding="utf-8")
        found = re.search(r'^\s+version: "([^"]+)"$', text, re.MULTILINE)
        self.assertIsNotNone(found, "SKILL.md metadata version line missing")
        self.assertEqual(found.group(1), manifest["version"])
