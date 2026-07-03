import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("agent_sessions", HERE / "agent-sessions.py")
agg = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(agg)


class ContextCompactionTests(unittest.TestCase):
    def test_observed_agents_block_becomes_file_ref(self):
        raw = "# AGENTS.md instructions for /repo\n\n<INSTRUCTIONS>huge policy</INSTRUCTIONS>"
        self.assertEqual(agg.clean_text(raw), "[ref:file name=AGENTS.md]")
        self.assertTrue(agg.is_wrapper_msg(raw))

    def test_observed_skill_block_becomes_skill_ref(self):
        raw = "<skill>\n<name>rp-build-cli</name>\n<path>/tmp/SKILL.md</path>\nbody\n</skill>"
        self.assertEqual(agg.clean_text(raw), "[ref:skill name=rp-build-cli]")
        self.assertTrue(agg.is_wrapper_msg(raw))

    def test_mixed_text_is_retained(self):
        raw = "Before <skill><name>caveman</name>bulk</skill> after"
        self.assertEqual(agg.clean_text(raw), "Before [ref:skill name=caveman] after")
        self.assertFalse(agg.is_wrapper_msg(raw))

    def test_explicit_file_metadata_is_compacted_and_deduped(self):
        raw = (
            '<user_instructions><file path="/repo/AGENTS.md">one</file>'
            '<file name="AGENTS.md">two</file></user_instructions>'
        )
        self.assertEqual(agg.clean_text(raw), "[ref:file name=AGENTS.md]")

    def test_nested_and_adjacent_wrappers(self):
        raw = (
            "a<system-reminder><environment_context>bulk</environment_context></system-reminder>"
            "<task-notification>more</task-notification>b"
        )
        self.assertEqual(agg.clean_text(raw), "a b")

    def test_literal_nested_wrapper_example_does_not_break_outer_match(self):
        raw = "<user_instructions>Example: <skill> without a close</user_instructions>"
        self.assertEqual(agg.clean_text(raw), "")

    def test_unclosed_wrapper_is_preserved(self):
        raw = "hello <user_instructions>keep this"
        self.assertEqual(agg._compact_injected_context(raw), raw)
        self.assertFalse(agg.is_wrapper_msg(raw))

    def test_ordinary_markup_is_not_compacted(self):
        raw = "Explain <file>this example</file> please"
        self.assertEqual(agg._compact_injected_context(raw), raw)
        self.assertEqual(agg.clean_text(raw), "Explain this example please")

    def test_scheduled_title_behavior_is_preserved(self):
        raw = '<scheduled-task name="Daily brief">bulk</scheduled-task>'
        self.assertEqual(agg.clean_title(raw), "\u23f0 Daily brief")
        self.assertTrue(agg.is_wrapper_msg(raw))

    def test_claude_message_output_compacts_mixed_turn(self):
        raw = "question <skill><name>caveman</name>bulk</skill>"
        row = {"type": "user", "message": {"content": raw}}
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "session.jsonl"
            path.write_text(json.dumps(row) + "\n")
            self.assertEqual(
                agg.claude_messages(str(path)),
                [{"role": "user", "text": "question  [ref:skill name=caveman]"}],
            )


class CacheVersionTests(unittest.TestCase):
    def setUp(self):
        self.old_path = agg.CACHE_PATH
        self.old_cache = agg._CACHE
        self.old_new_cache = agg._NEW_CACHE
        self.temp = tempfile.TemporaryDirectory()
        agg.CACHE_PATH = Path(self.temp.name) / "cache.json"

    def tearDown(self):
        agg.CACHE_PATH = self.old_path
        agg._CACHE = self.old_cache
        agg._NEW_CACHE = self.old_new_cache
        self.temp.cleanup()

    def test_old_cache_is_invalidated(self):
        agg.CACHE_PATH.write_text(json.dumps({"/old": {"mtime": 1, "rec": {}}}))
        agg.load_cache()
        self.assertEqual(agg._CACHE, {})

    def test_saved_cache_includes_version(self):
        agg._NEW_CACHE = {"/new": {"mtime": 2, "rec": {"title": "x"}}}
        agg.save_cache()
        data = json.loads(agg.CACHE_PATH.read_text())
        self.assertEqual(data["__format_version__"], agg.CACHE_FORMAT_VERSION)
        self.assertIn("/new", data)


if __name__ == "__main__":
    unittest.main()
