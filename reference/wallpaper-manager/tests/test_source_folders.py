"""Mounted drive places and independent multi-folder source discovery."""
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from PIL import Image

import wallpaper_add as core
import wallpaper_manager as manager
import wallpaper_sources as sources


class MountedPlacesTests(unittest.TestCase):
    def test_mounted_drives_spaces_and_read_only_locations(self):
        info = r'''1 0 0:1 / / rw - btrfs /dev/root rw
2 1 0:1 /@home /home rw - btrfs /dev/root rw
3 1 8:2 / /run/media/user/My\040Drive ro - fuseblk /dev/sdb2 ro
4 1 8:3 / /mnt/Art\134Store rw - ext4 /dev/sdb3 rw
5 1 0:4 / /home/user/CloudDrive rw - fuse.rclone remote: rw
6 1 8:4 / /boot rw - vfat /dev/sda1 rw
7 1 0:5 / /run/user/1000/gvfs rw - fuse.gvfsd-fuse gvfsd-fuse rw
8 1 0:6 / /proc rw - proc proc rw
9 1 0:7 / /media/Network rw - cifs //server/share rw
10 1 8:2 / /run/media/user/My\040Drive ro - fuseblk /dev/sdb2 ro
'''
        places = sources.mounted_places(info, Path('/home/user'))
        by_path = {place['path']: place for place in places}
        self.assertEqual(places[0]['path'], '/home/user')
        self.assertTrue(by_path['/run/media/user/My Drive']['read_only'])
        self.assertIn('/mnt/Art\\Store', by_path)
        self.assertIn('/home/user/CloudDrive', by_path)
        self.assertIn('/media/Network', by_path)
        self.assertNotIn('/boot', by_path)
        self.assertNotIn('/home', by_path)
        self.assertNotIn('/run/user/1000/gvfs', by_path)
        self.assertEqual(len(places), len(by_path))

    def test_places_action_reads_metadata_without_scanning_contents(self):
        with patch.object(sources, 'mounted_places', return_value=[{'name': 'Drive', 'path': '/mnt/drive'}]), \
                patch.object(sources, 'discover') as scan:
            result = manager.execute({'action': 'browser-places'})
        self.assertEqual(result['places'][0]['path'], '/mnt/drive')
        scan.assert_not_called()


class FolderBatchScanTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.base = Path(self.temp.name)
        self.first = self.base / 'Drive one' / 'Anime'
        self.second = self.base / 'Drive #two' / 'Anime'
        for folder in [self.first, self.second]:
            folder.mkdir(parents=True)
            Image.new('RGB', (16, 16), '#223344').save(folder / 'wallpaper.png')
        self.child = self.first / 'Nested'; self.child.mkdir()
        Image.new('RGB', (16, 16)).save(self.child / 'child.png')
        self.records = patch.object(sources.removal, 'list_records', return_value={})
        self.records.start()

    def tearDown(self):
        self.records.stop()
        self.temp.cleanup()

    def scan(self, paths=None, recursive=False):
        return manager.execute({'action': 'discover-folders', 'paths': [str(path) for path in (paths or [self.first, self.second])], 'recursive': recursive})['folder_batches']

    def test_same_named_folders_on_different_drives_stay_separate(self):
        rows = self.scan()
        self.assertEqual([row['folder'] for row in rows], [str(self.first), str(self.second)])
        for row, folder in zip(rows, [self.first, self.second]):
            self.assertEqual(len(row['candidates']), 1)
            self.assertEqual(row['candidates'][0]['source'], str(folder / 'wallpaper.png'))
            self.assertEqual(row['candidates'][0]['group'], '')

    def test_missing_drive_does_not_lose_other_folder_results(self):
        rows = self.scan([self.first, self.base / 'disconnected'])
        self.assertEqual(len(rows[0]['candidates']), 1)
        self.assertEqual(rows[1]['candidates'], [])
        self.assertIn('no longer mounted', rows[1]['issues'][0]['reason'])

    def test_unreadable_folder_is_reported_without_walking(self):
        real_access = os.access
        with patch.object(sources.os, 'access', side_effect=lambda path, mode: False if path == self.second else real_access(path, mode)):
            rows = self.scan()
        self.assertEqual(len(rows[0]['candidates']), 1)
        self.assertIn('cannot be read', rows[1]['issues'][0]['reason'])

    def test_recursion_stays_opt_in_and_external_links_are_excluded(self):
        (self.first / 'outside.png').symlink_to(self.second / 'wallpaper.png')
        self.assertEqual(len(self.scan()[0]['candidates']), 1)
        self.assertEqual(len(self.scan(recursive=True)[0]['candidates']), 2)

    def test_parent_child_selections_give_child_its_own_wallpapers(self):
        rows = self.scan([self.first, self.child], recursive=True)
        self.assertEqual([Path(row['candidates'][0]['source']).name for row in rows], ['wallpaper.png', 'child.png'])

    def test_duplicate_folder_choices_are_scanned_once(self):
        rows = self.scan([self.first, self.first / '..' / 'Anime'])
        self.assertEqual(len(rows), 1)

    def test_installed_sources_are_marked_without_merging_folders(self):
        with patch.object(sources.removal, 'list_records', return_value={'installed': {'source_file': str(self.first / 'wallpaper.png')}}):
            rows = self.scan()
        self.assertTrue(rows[0]['candidates'][0]['installed'])
        self.assertFalse(rows[1]['candidates'][0]['installed'])

    def test_refuses_whole_computer_home_and_invalid_selections(self):
        for values in [[], [''], ['/'], [str(Path.home())], 'not a list']:
            with self.subTest(values=values), self.assertRaises(core.ImportFailure):
                sources.scan_folders(values)
