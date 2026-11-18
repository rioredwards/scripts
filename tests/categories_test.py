"""categories: pull, render, check against fixtures with the Asana call stubbed."""
import contextlib, importlib.machinery, importlib.util, io, json, os, tempfile, unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
loader = importlib.machinery.SourceFileLoader("categories", os.path.join(ROOT, "categories"))
spec = importlib.util.spec_from_loader("categories", loader)
cat = importlib.util.module_from_spec(spec)
loader.exec_module(cat)

REG = {
    "asana": {"project": "1", "category_field": "2"},
    "categories": [
        {"name": "Work App", "slug": "work-app", "definition": "The work app."},
        {"name": "Tools", "slug": "tools", "definition": "Utilities."},
    ],
    "areas": [
        {"name": "QC", "slug": "qc", "category": "work-app", "asana_gid": "10", "definition": "QC."},
        {"name": "Labels", "slug": "labels", "category": "work-app", "asana_gid": "11", "definition": "Labels."},
    ],
}
OPTIONS = [{"gid": "10", "name": "QC", "enabled": True}, {"gid": "11", "name": "Labels", "enabled": True}]
VOCAB = "# Vocab\n\n## Work categories\n\n%s\n%s\n\nClassify by the goal and the interface.\n" % (cat.BEGIN, cat.END)


class Categories(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        cat.REGISTRY = os.path.join(self.tmp.name, "categories.json")
        cat.VOCAB = os.path.join(self.tmp.name, "VOCABULARY.md")
        self.write(cat.REGISTRY, json.dumps(REG))
        self.write(cat.VOCAB, VOCAB)
        self.options = [dict(o) for o in OPTIONS]
        cat.send = lambda url: {"data": {"enum_options": self.options}}

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, path, text):
        with open(path, "w") as f:
            f.write(text)

    def read(self, path):
        with open(path) as f:
            return f.read()

    def run_cmd(self, name):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            rc = cat.main([name])
        return rc, out.getvalue()

    def test_clean_check_passes(self):
        self.assertEqual(self.run_cmd("render")[0], 0)
        rc, out = self.run_cmd("check")
        self.assertEqual((rc, out), (0, "categories: in sync\n"))

    def test_render_is_idempotent_and_keeps_rule(self):
        self.run_cmd("render")
        once = self.read(cat.VOCAB)
        self.run_cmd("render")
        self.assertEqual(self.read(cat.VOCAB), once)
        self.assertIn("- **Work App:** The work app. Areas: QC, Labels.\n- **Tools:** Utilities.\n", once)
        self.assertIn("Classify by the goal and the interface.", once)

    def test_new_asana_option_is_drift_then_pulled_without_category(self):
        self.run_cmd("render")
        self.options.append({"gid": "12", "name": "Revenue Tracker", "enabled": True})
        rc, out = self.run_cmd("check")
        self.assertEqual(rc, 1)
        self.assertIn("new Asana option 'Revenue Tracker'", out)
        self.assertEqual(json.loads(self.read(cat.REGISTRY)), REG)  # check never writes
        self.run_cmd("pull")
        area = json.loads(self.read(cat.REGISTRY))["areas"][-1]
        self.assertEqual((area["slug"], area["category"], area["asana_gid"]), ("revenue-tracker", None, "12"))
        rc, out = self.run_cmd("check")
        self.assertEqual(rc, 1)
        self.assertIn("area 'Revenue Tracker' has no category", out)

    def test_rename_disable_remove_detected_by_gid(self):
        self.options = [{"gid": "10", "name": "Quality", "enabled": False}]
        rc, out = self.run_cmd("pull")
        self.assertIn("renamed 'QC' -> 'Quality'", out)
        self.assertIn("'Quality' is disabled", out)
        self.assertIn("'Labels' (gid 11) was removed", out)
        areas = json.loads(self.read(cat.REGISTRY))["areas"]
        self.assertEqual([(a["slug"], a["name"], a.get("asana_state")) for a in areas],
                         [("qc", "Quality", "disabled"), ("labels", "Labels", "removed")])
        self.run_cmd("render")
        self.assertIn("- **Work App:** The work app.\n", self.read(cat.VOCAB))  # inactive areas drop out
        self.assertEqual(self.run_cmd("check")[0], 0)

    def test_hand_edited_vocabulary_is_drift(self):
        self.run_cmd("render")
        self.write(cat.VOCAB, self.read(cat.VOCAB).replace("Utilities.", "Utilities and more."))
        rc, out = self.run_cmd("check")
        self.assertEqual(rc, 1)
        self.assertIn("Work categories section differs from the registry", out)

    def test_missing_markers_and_bad_json_fail_loud(self):
        self.write(cat.VOCAB, "# Vocab\n")
        with self.assertRaisesRegex(SystemExit, "marker"):
            self.run_cmd("render")
        self.write(cat.REGISTRY, "{nope")
        with self.assertRaisesRegex(SystemExit, "bad JSON"):
            self.run_cmd("check")

    def test_no_token_fails_loud(self):
        cat.token.cache_clear()
        old = os.environ["PATH"]
        os.environ["PATH"] = self.tmp.name  # no keyfor here
        self.write(os.path.join(self.tmp.name, "keyfor"), "#!/bin/sh\nexit 1\n")
        os.chmod(os.path.join(self.tmp.name, "keyfor"), 0o755)
        try:
            with self.assertRaisesRegex(SystemExit, "no ASANA_PAT"):
                cat.token()
        finally:
            os.environ["PATH"] = old
            cat.token.cache_clear()


if __name__ == "__main__":
    unittest.main()
