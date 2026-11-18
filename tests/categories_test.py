"""categories: pull, render, check against fixtures with the Asana call stubbed."""
import contextlib, importlib.machinery, importlib.util, io, json, os, tempfile, unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
loader = importlib.machinery.SourceFileLoader("categories", os.path.join(ROOT, "categories"))
spec = importlib.util.spec_from_loader("categories", loader)
cat = importlib.util.module_from_spec(spec)
loader.exec_module(cat)
GH = cat.gh

REG = {
    "asana": {"project": "1", "category_field": "2"},
    "categories": [
        {"name": "Work App", "slug": "work-app", "definition": "The work app.", "repos": ["o/r", "o/other"], "areas": [
            {"name": "QC", "slug": "qc", "asana_gid": "10", "definition": "QC and OCR work.", "exclude": "Not QC."},
            {"name": "Labels", "slug": "labels", "asana_gid": "11", "definition": "Labels."},
            {"name": "Other", "slug": "other", "asana_gid": "13", "definition": "Rest."},
        ]},
        {"name": "Tools", "slug": "tools", "definition": "Utilities.", "areas": [
            {"name": "Mac", "slug": "mac", "definition": "Mac work."},
        ]},
    ],
    "label_repos": ["o/r"],
    "unplaced": [],
}
OPTIONS = [{"gid": "10", "name": "QC", "enabled": True}, {"gid": "11", "name": "Labels", "enabled": True},
           {"gid": "13", "name": "Other", "enabled": True}]
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
        # GitHub labels in repo o/r: everything the registry wants, plus an extra.
        self.labels = [{"name": "scope:qc", "color": "0E8A16", "description": "QC"},
                       {"name": "scope:labels", "color": "5319E7", "description": "Labels"},
                       {"name": "scope:auth", "color": "5319E7", "description": "Auth"}]
        self.gh_calls = []
        cat.gh = self.fake_gh

    def fake_gh(self, *args):
        self.gh_calls.append(list(args))
        if args[:2] == ("label", "list"):
            self.assertEqual(args[2:4], ("--repo", "o/r"))
            return json.dumps(self.labels)
        return ""

    def writes(self):
        return [c for c in self.gh_calls if c[:2] != ["label", "list"]]

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, path, text):
        with open(path, "w") as f:
            f.write(text)

    def read(self, path):
        with open(path) as f:
            return f.read()

    def run_cmd(self, *argv):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            rc = cat.main(list(argv))
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
        self.assertIn("- **Work App:** The work app. Areas: QC, Labels, Other.\n- **Tools:** Utilities. Areas: Mac.\n", once)
        self.assertIn("Classify by the goal and the interface.", once)

    def test_new_asana_option_is_drift_then_pulled_into_unplaced(self):
        self.run_cmd("render")
        self.options.append({"gid": "12", "name": "Revenue Tracker", "enabled": True})
        rc, out = self.run_cmd("check")
        self.assertEqual(rc, 1)
        self.assertIn("new Asana option 'Revenue Tracker'", out)
        self.assertEqual(json.loads(self.read(cat.REGISTRY)), REG)  # check never writes
        self.run_cmd("pull")
        reg = json.loads(self.read(cat.REGISTRY))
        self.assertEqual(reg["unplaced"], [{"name": "Revenue Tracker", "slug": "revenue-tracker", "asana_gid": "12",
                                            "definition": ""}])
        self.assertEqual(reg["categories"], REG["categories"])
        rc, out = self.run_cmd("check")
        self.assertEqual((rc, out), (1, "area 'Revenue Tracker' is unplaced: place it under a category in %s\n"
                                        % cat.REGISTRY))  # no tag or label drift: unplaced areas get neither
        self.run_cmd("render")
        self.assertNotIn("Revenue Tracker", self.read(cat.VOCAB))

    def test_unplaced_area_updates_in_place_and_placing_it_clears_drift(self):
        reg = json.loads(json.dumps(REG))
        reg["unplaced"] = [{"name": "Rev", "slug": "rev", "asana_gid": "12", "definition": "Revenue."}]
        self.write(cat.REGISTRY, json.dumps(reg))
        self.options.append({"gid": "12", "name": "Revenue", "enabled": False})
        out = self.run_cmd("pull")[1]
        self.assertIn("renamed 'Rev' -> 'Revenue'", out)
        self.assertEqual(json.loads(self.read(cat.REGISTRY))["unplaced"],
                         [{"name": "Revenue", "slug": "rev", "asana_gid": "12", "definition": "Revenue.",
                           "asana_state": "disabled"}])
        self.options[-1]["enabled"] = True
        self.run_cmd("pull")
        reg = json.loads(self.read(cat.REGISTRY))
        reg["categories"][0]["areas"].append(reg["unplaced"].pop())
        self.write(cat.REGISTRY, json.dumps(reg))
        self.labels.append({"name": "scope:rev", "color": "5319E7", "description": "Revenue"})
        self.run_cmd("render")
        self.assertIn("Areas: QC, Labels, Other, Revenue.", self.read(cat.VOCAB))
        self.assertEqual(self.run_cmd("check"), (0, "categories: in sync\n"))

    def test_old_flat_shape_and_duplicate_area_slugs_fail_loud(self):
        reg = json.loads(json.dumps(REG))
        reg["unplaced"] = [{"name": "Mac 2", "slug": "mac", "definition": ""}]
        self.write(cat.REGISTRY, json.dumps(reg))
        with self.assertRaisesRegex(SystemExit, "duplicate area slug.*mac"):
            self.run_cmd("render")
        reg = json.loads(json.dumps(REG))
        reg["areas"] = []
        self.write(cat.REGISTRY, json.dumps(reg))
        with self.assertRaisesRegex(SystemExit, "top-level 'areas'"):
            self.run_cmd("render")

    def test_rename_disable_remove_detected_by_gid(self):
        self.options = [{"gid": "10", "name": "Quality", "enabled": False}]
        rc, out = self.run_cmd("pull")
        self.assertIn("renamed 'QC' -> 'Quality'", out)
        self.assertIn("'Quality' is disabled", out)
        self.assertIn("'Labels' (gid 11) was removed", out)
        areas = [a for c in json.loads(self.read(cat.REGISTRY))["categories"] for a in c["areas"]]
        self.assertEqual([(a["slug"], a["name"], a.get("asana_state")) for a in areas],
                         [("qc", "Quality", "disabled"), ("labels", "Labels", "removed"),
                          ("other", "Other", "removed"), ("mac", "Mac", None)])
        self.run_cmd("render")
        self.assertIn("- **Work App:** The work app.\n", self.read(cat.VOCAB))  # inactive areas drop out
        self.assertEqual(self.run_cmd("check"), (0, "categories: in sync\n"))  # scope:qc etc. are now extras

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

    def test_labels_dry_run_plans_and_never_writes(self):
        self.labels = [{"name": "scope:qc", "color": "0E8A16", "description": "QC scans"},
                       {"name": "scope:auth", "color": "5319E7", "description": "Auth"}]
        rc, out = self.run_cmd("labels")
        self.assertEqual(rc, 0)
        self.assertEqual(out, "o/r: create scope:labels (Labels, #5319E7)\n"
                              "o/r: scope:auth kept, not in registry\n"
                              "dry run: `categories labels --apply` makes these changes\n")
        self.assertEqual(self.writes(), [])

    def test_repo_in_repos_but_not_label_repos_gets_no_labels(self):
        # o/other is in the category's `repos` but not `label_repos`: fake_gh fails on any other repo.
        self.run_cmd("labels", "--apply")
        self.run_cmd("check")
        self.assertTrue(all(c[c.index("--repo") + 1] == "o/r" for c in self.gh_calls))

    def test_labels_apply_only_creates_missing(self):
        self.labels = [{"name": "scope:qc", "color": "0E8A16", "description": "QC scans"},
                       {"name": "scope:auth", "color": "5319E7", "description": "Auth"}]
        rc, out = self.run_cmd("labels", "--apply")
        self.assertEqual(rc, 0)
        # scope:qc keeps its richer description and color; scope:auth (extra) is kept too.
        self.assertEqual(self.writes(), [
            ["label", "create", "scope:labels", "--repo", "o/r", "--color", "5319E7", "--description", "Labels"]])
        self.assertNotIn("dry run", out)

    def test_check_reports_label_drift(self):
        self.run_cmd("render")
        self.labels = [{"name": "scope:qc", "color": "0E8A16", "description": "QC scans"}]
        rc, out = self.run_cmd("check")
        self.assertEqual(rc, 1)
        self.assertIn("o/r: label scope:labels missing (run `categories labels --apply`)", out)
        self.assertNotIn("scope:qc", out)  # a description differing from the Asana name is not drift
        self.assertEqual(self.writes(), [])

    def test_gh_failure_fails_loud(self):
        old = os.environ["PATH"]
        os.environ["PATH"] = self.tmp.name
        self.write(os.path.join(self.tmp.name, "gh"), "#!/bin/sh\necho 'auth expired' >&2\nexit 1\n")
        os.chmod(os.path.join(self.tmp.name, "gh"), 0o755)
        try:
            with self.assertRaisesRegex(SystemExit, "auth expired"):
                GH("label", "list")
        finally:
            os.environ["PATH"] = old

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
