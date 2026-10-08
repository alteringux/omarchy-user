#!/usr/bin/env python3
"""Keep the first-party product catalog aligned with plugin manifests."""

import json
from pathlib import Path
import re
import shutil
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]
PLUGIN_ROOT = ROOT / "plugins"
README = ROOT / "README.md"
TEARDOWN = ROOT / "docs/prds/omarchy-plugin-product-teardown.md"
AUDIT = ROOT / "docs/prds/evidence/05-click-paths/touchpoints.json"
PLUGIN_ID = re.compile(r"^\|\s*`(alteringux\.[a-z0-9.-]+)`\s*\|", re.MULTILINE)
TEARDOWN_PLUGIN = re.compile(r"^\|\s*`([a-z0-9.-]+)`\s*\|", re.MULTILINE)


def catalog_ids(readme_text):
    try:
        section = readme_text.split("## Plugins\n", 1)[1].split("\n## ", 1)[0]
    except IndexError:
        return []
    return PLUGIN_ID.findall(section)


def teardown_ids(teardown_text):
    try:
        section = teardown_text.split("## Per-plugin design choices\n", 1)[1].split("\n## ", 1)[0]
    except IndexError:
        return []
    return [f"alteringux.{plugin}" for plugin in TEARDOWN_PLUGIN.findall(section)]


def manifest_ids(plugin_root):
    ids = []
    for manifest in sorted(plugin_root.glob("alteringux.*/manifest.json")):
        if manifest.parent.name == "alteringux.kit":
            continue
        data = json.loads(manifest.read_text(encoding="utf-8"))
        plugin_id = data.get("id")
        if not isinstance(plugin_id, str) or not plugin_id.startswith("alteringux."):
            raise AssertionError(f"invalid first-party plugin id in {manifest}")
        if plugin_id != manifest.parent.name:
            raise AssertionError(f"manifest id {plugin_id} does not match {manifest.parent.name}")
        ids.append(plugin_id)
    return ids


def inventory_diff(catalog, manifests):
    return {
        "missing": sorted(set(manifests) - set(catalog)),
        "extra": sorted(set(catalog) - set(manifests)),
        "duplicate": sorted({item for item in catalog if catalog.count(item) > 1}),
    }


class PluginCatalogTest(unittest.TestCase):
    def test_catalog_matches_all_first_party_product_manifests(self):
        catalog = catalog_ids(README.read_text(encoding="utf-8"))
        teardown = teardown_ids(TEARDOWN.read_text(encoding="utf-8"))
        manifests = manifest_ids(PLUGIN_ROOT)
        self.assertEqual(len(manifests), 42, "update this expected count with an intentional inventory change")
        self.assertEqual(inventory_diff(catalog, manifests), {"missing": [], "extra": [], "duplicate": []})
        self.assertEqual(inventory_diff(teardown, manifests), {"missing": [], "extra": [], "duplicate": []})
        self.assertTrue(AUDIT.is_file(), "all first-party plugins need an explicit audit record")
        audit = json.loads(AUDIT.read_text(encoding="utf-8"))
        self.assertEqual(audit["schemaVersion"], 1)
        self.assertEqual(inventory_diff([row["id"] for row in audit["plugins"]], manifests),
                         {"missing": [], "extra": [], "duplicate": []})
        report = ROOT / "docs/prds/omarchy-plugin-click-path-audit.md"
        self.assertEqual(inventory_diff(PLUGIN_ID.findall(report.read_text(encoding="utf-8")), manifests),
                         {"missing": [], "extra": [], "duplicate": []})

    def test_audit_sources_and_evidence_are_explicit(self):
        audit = json.loads(AUDIT.read_text(encoding="utf-8"))
        required = {"id", "source", "entry", "calls", "reads", "writes", "resets",
                    "expected", "observed", "status", "evidence"}
        statuses = {"pending", "source-reviewed", "native-pass", "failed", "not-applicable"}
        for row in audit["plugins"]:
            ids = [item["id"] for item in row["touchpoints"]]
            self.assertEqual(len(ids), len(set(ids)), row["id"])
            self.assertTrue(ids, row["id"])
            for item in row["touchpoints"]:
                with self.subTest(plugin=row["id"], touchpoint=item["id"]):
                    self.assertTrue(required <= item.keys())
                    self.assertIn(item["status"], statuses)
                    source = item["source"]
                    path = Path(source["path"])
                    self.assertFalse(path.is_absolute())
                    self.assertNotIn("..", path.parts)
                    self.assertTrue(str(path).startswith(f"plugins/{row['id']}/"))
                    lines = (ROOT / path).read_text(encoding="utf-8").splitlines()
                    self.assertGreaterEqual(source["line"], 1)
                    self.assertLessEqual(source["line"], len(lines))
                    if item["status"] == "native-pass":
                        self.assertTrue(item["observed"])
                        self.assertTrue(item["evidence"], "native passes need direct interaction evidence")
                    for evidence in item["evidence"]:
                        path = Path(evidence)
                        self.assertFalse(path.is_absolute())
                        self.assertNotIn("..", path.parts)
                        self.assertTrue((ROOT / path).is_file())

    def test_fixture_reports_missing_extra_and_duplicate_ids(self):
        with self.subTest("missing and duplicate catalog row"):
            result = inventory_diff(
                ["alteringux.alpha", "alteringux.alpha", "alteringux.outside"],
                ["alteringux.alpha", "alteringux.beta"],
            )
            self.assertEqual(result, {
                "missing": ["alteringux.beta"],
                "extra": ["alteringux.outside"],
                "duplicate": ["alteringux.alpha"],
            })

    def test_shared_kit_and_third_party_manifests_are_out_of_catalog_scope(self):
        ids = manifest_ids(PLUGIN_ROOT)
        self.assertNotIn("alteringux.kit", ids)
        self.assertEqual(len(ids), 42)

class HostManifestTest(unittest.TestCase):
    def test_host_validator_accepts_every_product_manifest(self):
        omarchy = shutil.which("omarchy")
        self.assertIsNotNone(omarchy, "run repository checks on an Omarchy host")
        failures = []
        for manifest in sorted(PLUGIN_ROOT.glob("alteringux.*/manifest.json")):
            if manifest.parent.name == "alteringux.kit":
                continue
            result = subprocess.run(
                [omarchy, "plugin", "validate", str(manifest.parent)],
                capture_output=True,
                text=True,
            )
            if result.returncode:
                detail = (result.stderr or result.stdout).strip()
                failures.append(f"{manifest.parent.name}: {detail}")
        self.assertEqual(failures, [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
