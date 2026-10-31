"""Mixed-media batches, using disposable homes and no real desktop changes."""
from argparse import Namespace
import json
from pathlib import Path
import shutil
import unittest
from unittest.mock import patch

from PIL import Image
import test_importer as fixture
import wallpaper_add as core
import wallpaper_bulk as bulk
import wallpaper_remove as removal


class BulkTests(unittest.TestCase):
    setUp = fixture.ImporterTests.setUp
    tearDown = fixture.ImporterTests.tearDown
    fake_run = fixture.ImporterTests.fake_run
    args = fixture.ImporterTests.args
    install = fixture.ImporterTests.install
    records = fixture.ImporterTests.records
    project_folder = fixture.ImporterTests.project_folder

    def batch(self, *values):
        with patch.object(core.os, 'nice'):
            return core.main(list(values))

    def second_image(self, name='Other.png'):
        path = self.base / name; Image.new('RGB', (16, 16), '#778899').save(path)
        return path

    def test_mixed_image_video_workshop_batch_preserves_real_video(self):
        video = self.base / 'Live Video.MP4'; video.write_bytes(b'actual video payload')
        project = self.project_folder('scene', 'scene.pkg', fixture.package({'full.tex': fixture.texture()}))
        result = self.batch('--bulk-add', str(self.source), str(video), str(project), '--target', 'both', '--allow-static-scenes', '--no-apply', '--yes', '--non-interactive')
        self.assertEqual(result, 0)
        records = self.records(); self.assertEqual(len(records), 3)
        self.assertEqual(records['live-video']['type'], 'video')
        self.assertEqual(Path(records['live-video']['video']).read_bytes(), video.read_bytes())
        self.assertEqual(sum(r['type'] == 'static' for r in records.values()), 2)
        self.assertTrue(all(r['targets'] == ['omarchy', 'daemon-os'] for r in records.values()))
        self.assertTrue(all(c[0] not in {'omarchy', 'caelestia'} for c in self.calls))
        receipt = list((self.project / 'data/batches').glob('*-add.json'))
        self.assertEqual(json.loads(receipt[0].read_text())['counts']['done'], 3)

    def test_discovery_treats_workshop_as_one_and_ignores_ready_copies(self):
        root = self.base / 'Downloads'; root.mkdir()
        shutil.copy2(self.source, root / 'Wallpaper.png')
        project = self.project_folder('scene', 'scene.pkg', fixture.package({'full.tex': fixture.texture()}))
        shutil.copytree(project, root / '12345')
        extra = root / '12345/ready'; extra.mkdir(); shutil.copy2(self.source, extra / 'copy.png')
        ready = root / 'ready'; ready.mkdir(); shutil.copy2(self.source, ready / 'copy.png')
        shutil.copy2(self.source, root / 'preview.jpg')
        sources, issues = bulk.discover([str(root), str(root / '12345')], root)
        self.assertEqual(len(sources), 2); self.assertFalse(issues)
        self.assertEqual({s['asset'].suffix for s in sources}, {'.png', '.pkg'})

    def test_selection_ranges_and_exclusions_never_default_to_all(self):
        self.assertEqual(bulk.select_numbers('all,!2,!4-5', 6), [0, 2, 5])
        self.assertEqual(bulk.select_numbers('1,3-4,3', 4), [0, 2, 3])
        for text in ['', '0', '4-2', 'all,!1-4', '100000', '-1', 'banana']:
            with self.assertRaises(core.ImportFailure): bulk.select_numbers(text, 4)

    def test_batch_dry_run_writes_nothing_and_never_calls_aether(self):
        other = self.second_image()
        self.assertEqual(self.batch('--bulk-add', str(self.source), str(other), '--target', 'daemon-os', '--dry-run', '--non-interactive'), 0)
        self.assertFalse(core.Locations().registry.exists()); self.assertFalse(self.calls)
        self.assertFalse((self.project / 'data').exists())
        self.assertFalse(core.Locations().state.exists())

    def test_unconfirmed_noninteractive_batch_does_not_write(self):
        self.assertEqual(self.batch('--bulk-add', str(self.source), '--non-interactive'), 1)
        self.assertFalse(core.Locations().registry.exists()); self.assertFalse(self.calls)

    def test_invalid_and_failed_sources_do_not_stop_valid_imports(self):
        other = self.second_image(); bad = self.base / 'broken.png'; bad.write_text('not an image')
        self.assertEqual(self.batch('--bulk-add', str(bad), str(self.base / 'missing.mp4'), str(self.source), str(other), '--yes', '--no-apply', '--non-interactive'), 1)
        self.assertEqual(len(self.records()), 2)
        receipt = json.loads(next((self.project / 'data/batches').glob('*.json')).read_text())
        self.assertEqual(receipt['counts']['done'], 2); self.assertEqual(receipt['counts']['failed'], 2)

    def test_preexisting_and_duplicate_inputs_are_not_reimported(self):
        self.install(); self.calls.clear()
        other = self.second_image()
        self.assertEqual(self.batch('--bulk-add', str(self.source), str(other), str(other), '--yes', '--no-apply', '--non-interactive'), 0)
        self.assertEqual(len(self.records()), 2)
        self.assertEqual(sum(Path(c[0]).name == 'aether' for c in self.calls), 1)

    def test_legacy_workshop_id_is_skipped_even_with_curated_theme_name(self):
        record = self.install('--name', 'Curated Ink')
        project = self.project_folder('scene', 'scene.pkg', fixture.package({'full.tex': fixture.texture()}))
        numbered = project.parent / '123456789'; project.rename(numbered)
        registry = core.read_json(core.Locations().registry)
        old = registry['wallpapers'][record['slug']]; old['id'] = '123456789'; old.pop('source_file', None)
        core.Locations().registry.write_text(json.dumps(registry)); self.calls.clear()
        self.assertEqual(self.batch('--bulk-add', str(numbered), '--allow-static-scenes', '--yes', '--no-apply', '--non-interactive'), 0)
        self.assertEqual(list(self.records()), ['curated-ink']); self.assertFalse(self.calls)

    def test_same_name_collision_does_not_overwrite_first(self):
        a = self.base / 'a'; b = self.base / 'b'; a.mkdir(); b.mkdir()
        shutil.copy2(self.source, a / 'same.png'); shutil.copy2(self.source, b / 'same.png')
        self.assertEqual(self.batch('--bulk-add', str(a / 'same.png'), str(b / 'same.png'), '--yes', '--no-apply', '--replace', '--non-interactive'), 0)
        self.assertEqual(len(self.records()), 1)
        self.assertEqual(self.records()['same']['source_file'], str(a / 'same.png'))

    def test_apply_runs_once_after_last_successful_import(self):
        other = self.second_image()
        with patch.object(core, 'activate') as apply:
            self.assertEqual(self.batch('--bulk-add', str(self.source), str(other), '--target', 'omarchy', '--yes', '--apply', '--non-interactive'), 0)
        apply.assert_called_once(); self.assertEqual(apply.call_args.args[0]['slug'], 'other')

    def test_no_static_consent_keeps_video_live_and_reports_scene_failure(self):
        video = self.base / 'Live.mp4'; video.write_bytes(b'video')
        project = self.project_folder('scene', 'scene.pkg', fixture.package({'full.tex': fixture.texture()}))
        self.assertEqual(self.batch('--bulk-add', str(project), str(video), '--yes', '--no-apply', '--non-interactive'), 1)
        self.assertEqual(list(self.records()), ['live']); self.assertEqual(self.records()['live']['type'], 'video')

    def test_auto_package_with_still_layer_and_video_chooses_video(self):
        project = self.project_folder('scene', 'scene.pkg', fixture.package({'full.tex': fixture.texture(), 'loop.mp4': b'video payload'}))
        self.assertEqual(self.batch('--bulk-add', str(project), '--yes', '--no-apply', '--non-interactive'), 0)
        record = next(iter(self.records().values())); self.assertEqual(record['type'], 'video')
        self.assertEqual(Path(record['video']).read_bytes(), b'video payload')

    def test_interactive_bulk_target_and_confirmation_are_asked_once(self):
        other = self.second_image()
        with patch.object(core.sys.stdin, 'isatty', return_value=True), patch('builtins.input', side_effect=['all', '2', '', 'n', 'y']) as ask:
            self.assertEqual(self.batch('--bulk-add', str(self.source), str(other)), 0)
        self.assertEqual(ask.call_count, 5)
        self.assertTrue(all(r['targets'] == ['daemon-os'] for r in self.records().values()))

    def test_bulk_removal_one_target_keeps_other_desktop_assets(self):
        one = self.install(); two = self.install('--name', 'Second')
        self.assertEqual(self.batch('--bulk-remove', one['slug'], two['slug'], '--target', 'omarchy', '--yes', '--non-interactive'), 0)
        self.assertEqual(len(self.records()), 2)
        for r in self.records().values():
            self.assertEqual(r['targets'], ['daemon-os'])
            self.assertTrue(Path(r['daemon_alias']).is_file()); self.assertTrue(Path(r['colors_toml']).is_file())
        self.assertTrue(self.source.is_file())

    def test_bulk_remove_all_skips_active_and_removes_other_theme(self):
        one = self.install(); two = self.install('--name', 'Second')
        with patch.object(removal, 'active_wallpaper', return_value=('omarchy', one['slug'], Path(one['installed_image']))):
            self.assertEqual(self.batch('--bulk-remove', 'all', '--target', 'both', '--yes', '--non-interactive'), 0)
        self.assertEqual(list(self.records()), [one['slug']]); self.assertTrue(self.source.is_file())
        self.assertFalse(Path(two['installed_image']).exists())

    def test_bulk_removal_confirms_once_and_deduplicates_names(self):
        one = self.install(); two = self.install('--name', 'Second')
        with patch.object(core.sys.stdin, 'isatty', return_value=True), patch('builtins.input', side_effect=['1-2', '2', 'y']) as ask:
            self.assertEqual(self.batch('--bulk-remove'), 0)
        self.assertEqual(ask.call_count, 3)
        self.assertTrue(all(r['targets'] == ['omarchy'] for r in self.records().values()))
        self.assertTrue(Path(one['installed_image']).is_file()); self.assertTrue(Path(two['installed_image']).is_file())

    def test_bulk_removal_dry_run_and_missing_confirmation_keep_registry(self):
        self.install(); self.install('--name', 'Second'); before = core.Locations().registry.read_bytes()
        self.assertEqual(self.batch('--bulk-remove', 'all', '--dry-run', '--non-interactive'), 0)
        self.assertEqual(self.batch('--bulk-remove', 'all', '--non-interactive'), 1)
        self.assertEqual(before, core.Locations().registry.read_bytes())

    def test_per_item_removal_backup_failure_rolls_back_and_batch_continues(self):
        one = self.install(); two = self.install('--name', 'Second')
        with patch.object(core, 'backup_metadata', side_effect=[core.ImportFailure('backup failure'), None]):
            self.assertEqual(self.batch('--bulk-remove', one['slug'], two['slug'], '--yes', '--non-interactive'), 1)
        self.assertEqual(list(self.records()), [one['slug']])
        self.assertTrue(Path(one['installed_image']).is_file()); self.assertFalse(Path(two['installed_image']).exists())

    def test_current_item_interrupt_rolls_back_removal(self):
        record = self.install(); before = core.Locations().registry.read_bytes()
        with patch.object(core, 'backup_metadata', side_effect=KeyboardInterrupt):
            self.assertEqual(self.batch('--bulk-remove', record['slug'], '--yes', '--non-interactive'), 130)
        self.assertEqual(before, core.Locations().registry.read_bytes())
        self.assertTrue(Path(record['daemon_alias']).is_file())


if __name__ == '__main__':
    unittest.main()
