import errno
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

loader = importlib.machinery.SourceFileLoader('enrich', str(Path(__file__).resolve().parents[1] / 'screenshot-enrich'))
spec = importlib.util.spec_from_loader(loader.name, loader)
m = importlib.util.module_from_spec(spec)
loader.exec_module(m)


def answer(category='development', evidence='text'):
    return {'answers': [{'type': 'choice', 'name': 'category', 'choice': category},
                        {'type': 'choice', 'name': 'evidence', 'choice': evidence}],
            'usage': {'input_tokens': 300}}


class WorkerTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).resolve()
        self.folder = self.root / 'screenshots'
        self.folder.mkdir()
        self.worker = m.Worker(self.folder, self.root / 'state')
        self.addCleanup(self.worker.db.close)
        self.clock = patch.object(m.time, 'time', return_value=100.)
        self.clock.start()
        self.addCleanup(self.clock.stop)
        self.ocr = patch.object(m, 'ocr', return_value='Useful OCR\n').start()
        self.decide = patch.object(m, 'decide', return_value=answer()).start()
        self.real_tag = m.tag
        self.tag = patch.object(m, 'tag', return_value=None).start()
        self.addCleanup(patch.stopall)

    def image(self, name='CleanShot_test.jpg'):
        path = self.folder / name
        path.write_bytes(b'image bytes')
        os.utime(path, (90., 90.))
        return path

    def ready(self):
        self.worker.scan()
        m.time.time.return_value = 110.
        return self.worker.scan()

    def test_requires_explicit_baseline(self):
        self.image()
        with self.assertRaisesRegex(RuntimeError, 'initialize'):
            self.worker.scan()
        self.ocr.assert_not_called()

    def test_baseline_excluded_new_image_enriched_once(self):
        old = self.image('old.jpg')
        self.worker.initialize()
        new = self.image()
        original = new.read_bytes()
        self.ready()
        self.worker.scan()
        self.assertFalse(Path(str(old) + '.txt').exists())
        self.assertEqual(Path(str(new) + '.txt').read_text(), 'Useful OCR\n')
        self.assertEqual(original, new.read_bytes())
        self.assertEqual(1, self.ocr.call_count)
        self.assertEqual(1, self.decide.call_count)
        self.tag.assert_called_once_with(new, 'development')

    def test_partial_save_waits_for_stability(self):
        self.worker.initialize()
        path = self.image()
        self.worker.scan()
        m.time.time.return_value = 101.
        path.write_bytes(b'changed image')
        self.worker.scan()
        self.ocr.assert_not_called()
        m.time.time.return_value = 110.
        os.utime(path, (90., 90.))
        self.worker.scan()
        m.time.time.return_value = 120.
        self.worker.scan()
        self.ocr.assert_called_once()

    def test_retry_keeps_ocr_and_paid_result(self):
        self.worker.initialize()
        path = self.image()
        self.tag.side_effect = OSError('tag unavailable')
        self.assertEqual(1, self.ready())
        self.assertTrue(Path(str(path) + '.txt').exists())
        self.tag.side_effect = None
        m.time.time.return_value = 800.
        self.worker.scan()
        self.ocr.assert_called_once()
        self.decide.assert_called_once()
        self.assertEqual('done', self.worker.db.execute('select status from files').fetchone()[0])

    def test_api_failure_leaves_ocr_then_retries(self):
        self.worker.initialize()
        path = self.image()
        self.decide.side_effect = RuntimeError('API unavailable')
        self.assertEqual(1, self.ready())
        self.assertTrue(Path(str(path) + '.txt').exists())
        self.decide.side_effect = None
        m.time.time.return_value = 800.
        self.worker.scan()
        self.ocr.assert_called_once()
        self.assertEqual(2, self.decide.call_count)

    def test_image_escalation_is_bounded(self):
        self.worker.initialize()
        path = self.image()
        self.decide.side_effect = [answer('unclear', 'image'), {'answers': [{'type': 'choice', 'name': 'category', 'choice': 'interface-design'}]}]
        self.ready()
        self.assertEqual([False, True], [c.args[2] if len(c.args) > 2 else False for c in self.decide.call_args_list])
        self.tag.assert_called_once_with(path, 'interface-design')

    def test_changed_pending_image_replaces_only_owned_sidecar(self):
        self.worker.initialize()
        path = self.image()
        self.tag.side_effect = OSError('tag unavailable')
        self.ready()
        path.write_bytes(b'new image contents')
        os.utime(path, (100., 100.))
        self.ocr.return_value = 'Updated OCR\n'
        self.tag.side_effect = None
        m.time.time.return_value = 800.
        self.worker.scan()
        m.time.time.return_value = 810.
        self.worker.scan()
        self.assertEqual('Updated OCR\n', Path(str(path) + '.txt').read_text())
        self.assertEqual('done', self.worker.db.execute('select status from files').fetchone()[0])

    def test_user_modified_owned_sidecar_remains_protected(self):
        self.worker.initialize()
        path = self.image()
        self.tag.side_effect = OSError('tag unavailable')
        self.ready()
        sidecar = Path(str(path) + '.txt')
        sidecar.write_text('User notes')
        path.write_bytes(b'new image contents')
        self.ocr.return_value = 'Updated OCR\n'
        m.time.time.return_value = 800.
        self.worker.scan()
        m.time.time.return_value = 810.
        self.worker.scan()
        self.assertEqual('User notes', sidecar.read_text())

    def test_image_changed_during_classification_recovers(self):
        self.worker.initialize()
        path = self.image()
        def change_image(*args):
            path.write_bytes(b'new image contents')
            os.utime(path, (100., 100.))
            return answer()
        self.decide.side_effect = change_image
        self.assertEqual(1, self.ready())
        self.tag.assert_not_called()
        self.decide.side_effect = None
        self.ocr.return_value = 'Updated OCR\n'
        m.time.time.return_value = 800.
        self.worker.scan()
        m.time.time.return_value = 810.
        self.assertEqual(0, self.worker.scan())
        self.assertEqual('Updated OCR\n', Path(str(path) + '.txt').read_text())
        self.tag.assert_called_once_with(path, 'development')

    def test_existing_sidecar_not_overwritten(self):
        self.worker.initialize()
        path = self.image()
        sidecar = Path(str(path) + '.txt')
        sidecar.write_text('My notes')
        self.assertEqual(1, self.ready())
        self.assertEqual('My notes', sidecar.read_text())
        self.decide.assert_not_called()

    def test_refusal_is_visible_not_guessed(self):
        self.worker.initialize()
        self.image()
        self.decide.return_value = {'answers': [{'type': 'refusal', 'name': 'category'}]}
        self.assertEqual(1, self.ready())
        self.tag.assert_not_called()

    def test_symlink_and_unrelated_files_are_ignored(self):
        self.worker.initialize()
        (self.folder / 'other.jpg').symlink_to(self.root / 'missing.jpg')
        (self.folder / 'notes.txt').write_text('notes')
        self.ready()
        self.ocr.assert_not_called()

    def test_baseline_is_not_reset_on_reinstall(self):
        self.worker.initialize()
        self.image()
        self.worker.initialize()
        self.ready()
        self.ocr.assert_called_once()

    def test_finder_tags_preserve_existing_and_replace_own(self):
        with patch.object(m, 'get_tags', return_value=['Important\n6', 'Screenshot: Reference\n0']), patch.object(m, 'command') as put:
            self.real_tag(Path('image.jpg'), 'development')
            self.assertEqual(['Important\n6', 'Screenshot: Development\n0'], plistlib.loads(bytes.fromhex(put.call_args.args[0][3])))


if __name__ == '__main__':
    unittest.main()
