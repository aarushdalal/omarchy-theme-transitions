"""GUI scans stay within the explicitly chosen folder; CLI recursion is unchanged."""
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from PIL import Image
import wallpaper_bulk as bulk
import wallpaper_manager as manager
import wallpaper_add as core

class ScanScopeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.base = Path(self.temp.name)
        self.chosen = self.base / 'Chosen'; self.chosen.mkdir()
        self.child = self.chosen / 'Nested'; self.child.mkdir()
        self.outside = self.base / 'Elsewhere'; self.outside.mkdir()
        for folder, name in [(self.chosen, 'chosen.png'), (self.child, 'nested.png'), (self.outside, 'outside.png')]:
            Image.new('RGB', (16,16)).save(folder / name)
        (self.chosen / 'outside-link.png').symlink_to(self.outside / 'outside.png')
        (self.chosen / 'outside-folder').symlink_to(self.outside, target_is_directory=True)

    def tearDown(self): self.temp.cleanup()

    def names(self, recursive):
        rows, issues = bulk.discover([str(self.chosen)], self.base, recursive=recursive)
        self.assertFalse(issues)
        return {r['asset'].name for r in rows}

    def test_default_gui_scan_is_shallow(self):
        with patch.object(manager.removal, 'list_records', return_value={}):
            rows = manager.execute({'action':'discover', 'paths':[str(self.chosen)]})['candidates']
        self.assertEqual([Path(r['source']).name for r in rows], ['chosen.png'])

    def test_recursive_scan_is_explicit_and_does_not_follow_external_links(self):
        self.assertEqual(self.names(False), {'chosen.png'})
        self.assertEqual(self.names(True), {'chosen.png', 'nested.png'})
        with patch.object(manager.removal, 'list_records', return_value={}):
            rows = manager.execute({'action':'discover','paths':[str(self.chosen)],'recursive':True})['candidates']
        self.assertEqual(len(rows), 2)

    def test_gui_refuses_home_root_and_empty_paths(self):
        for paths in [[], [''], [' '], ['/'], [str(Path.home())]]:
            with self.subTest(paths=paths), self.assertRaises(core.ImportFailure):
                manager.execute({'action':'discover','paths':paths})

    def test_shallow_scan_keeps_immediate_workshop_projects_as_one_source(self):
        p = self.chosen / '12345'; p.mkdir()
        (p / 'project.json').write_text('{"title":"Project", "type":"video", "file":"movie.mp4"}')
        (p / 'movie.mp4').write_bytes(b'video')
        Image.new('RGB',(16,16)).save(p/'preview.jpg')
        rows, issues = bulk.discover([str(self.chosen)], self.base, recursive=False)
        self.assertFalse(issues)
        self.assertEqual(len(rows),2)
        self.assertEqual(sum(r['asset'].name=='movie.mp4' for r in rows),1)
