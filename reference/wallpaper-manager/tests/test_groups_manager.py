"""Manager workflows in disposable homes; installed user themes are never reorganized."""
import json
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

import test_importer as fixture
import wallpaper_add as core
import wallpaper_groups as groups
import wallpaper_manager as manager
import wallpaper_remove as removal


class ManagerTests(unittest.TestCase):
    setUp = fixture.ImporterTests.setUp
    tearDown = fixture.ImporterTests.tearDown
    fake_run = fixture.ImporterTests.fake_run
    args = fixture.ImporterTests.args
    install = fixture.ImporterTests.install
    records = fixture.ImporterTests.records

    def edit(self, **request):
        with patch.object(removal, 'STOCK_THEMES', self.home / 'stock'):
            return manager.execute(request)

    def test_anime_names_are_never_automatically_grouped(self):
        record = self.install('--name', 'Satoru Gojo')
        self.assertEqual(record['group'], '')
        self.assertEqual(groups.group_for(record['slug']), '')

    def test_group_edits_first_rename_and_dissolve_keep_media_and_slugs(self):
        one = self.install('--name', 'One')
        two = self.install('--name', 'Two')
        images = {r['slug']: core.digest(r['image']) for r in [one, two]}
        self.edit(action='group', slugs=['one', 'two'], group='My Anime')
        self.edit(action='first', slugs=['two'])
        self.assertEqual(groups.members(self.records())['My Anime'], ['two', 'one'])
        self.edit(action='rename-group', old='My Anime', group='My New Group')
        self.assertEqual(groups.group_for('two'), 'My New Group')
        self.assertEqual(groups.load()['first']['My New Group'], 'two')
        self.edit(action='delete-group', old='My New Group')
        self.assertEqual(groups.group_for('one'), '')
        self.assertEqual(groups.group_for('two'), '')
        for record in [one, two]:
            self.assertEqual(core.digest(record['image']), images[record['slug']])
            self.assertTrue(Path(record['installed_theme']).is_dir())

    def test_ungrouped_override_wins_over_old_record_group(self):
        self.install('--group', 'Anime')
        self.edit(action='group', slugs=['evening-image'], group='')
        self.assertEqual(groups.group_for('evening-image', self.records()['evening-image']), '')

    def test_display_name_edit_preserves_stable_slug(self):
        record = self.install()
        self.edit(action='rename-theme', slugs=[record['slug']], title='My Evening')
        with patch.object(removal, 'STOCK_THEMES', self.home / 'stock'):
            self.assertEqual(manager.snapshot()['items'][0]['title'], 'My Evening')
        self.assertIn('evening-image', self.records())

    def test_gui_requires_confirmation_before_add_or_remove(self):
        for action in ['import', 'remove']:
            with self.assertRaisesRegex(core.ImportFailure, 'confirm'):
                manager.execute({'action': action, 'items': []})
        self.assertFalse(core.Locations().registry.exists())

    def test_structured_bulk_import_per_item_groups_and_failure_continuation(self):
        result = manager.execute({'action': 'import', 'confirmed': True, 'items': [
            {'source': str(self.source), 'title': 'One', 'group': 'Chosen'},
            {'source': str(self.base / 'missing.png'), 'title': 'Missing', 'group': ''},
            {'source': str(self.source), 'title': 'Two', 'group': ''}], 'target': 'both'})
        self.assertEqual([r['status'] for r in result['results']], ['done', 'failed', 'done'])
        self.assertEqual(groups.group_for('one'), 'Chosen')
        self.assertEqual(groups.group_for('two'), '')
        self.assertTrue(all(c[0] not in ['omarchy', 'caelestia'] for c in self.calls))

    def test_removal_protects_active_theme_and_preserves_original(self):
        record = self.install('--group', 'Chosen')
        with patch.object(removal, 'active_wallpaper', return_value=('omarchy', record['slug'], Path(record['image']))):
            result = manager.execute({'action': 'remove', 'confirmed': True, 'target': 'both', 'items': [{'slug': record['slug']}]})
        self.assertEqual(result['results'][0]['status'], 'failed')
        self.assertIn('currently active', result['results'][0]['details'])
        self.assertTrue(Path(record['installed_theme']).exists())
        with patch.object(removal, 'active_wallpaper', return_value=('omarchy', 'other', None)):
            result = manager.execute({'action': 'remove', 'confirmed': True, 'target': 'both', 'items': [{'slug': record['slug']}]})
        self.assertEqual(result['results'][0]['status'], 'done')
        self.assertTrue(self.source.is_file())
        self.assertNotIn(record['slug'], groups.load()['assignments'])

    def test_group_filtered_cli_bulk_remove_leaves_other_groups(self):
        one = self.install('--name', 'One', '--group', 'Remove me')
        self.install('--name', 'Two', '--group', 'Keep me')
        with patch.object(removal, 'active_wallpaper', return_value=('omarchy', 'other', None)), patch.object(core.os, 'nice'):
            self.assertEqual(core.main(['--bulk-remove', 'all', '--group', 'Remove me', '--yes', '--non-interactive']), 0)
        self.assertNotIn(one['slug'], self.records())
        self.assertIn('two', self.records())

    def test_dry_run_and_discovery_never_create_groups(self):
        result = manager.execute({'action': 'discover', 'paths': [str(self.source)]})
        self.assertEqual(result['candidates'][0]['group'], '')
        result = manager.execute({'action': 'import', 'confirmed': True, 'dry_run': True, 'items': [
            {'source': str(self.source), 'title': 'Gojo', 'group': 'Chosen'}]})
        self.assertEqual(result['results'][0]['status'], 'planned')
        self.assertFalse(groups.config_path().exists())
        self.assertFalse(core.Locations().registry.exists())

    def test_replacement_keeps_group_unless_explicitly_changed(self):
        self.install('--group', 'Chosen')
        self.install('--replace')
        self.assertEqual(groups.group_for('evening-image'), 'Chosen')
        self.install('--replace', '--group', '')
        self.assertEqual(groups.group_for('evening-image'), '')

    def test_failed_import_rolls_back_group_metadata(self):
        with patch.object(core, 'backup_metadata', side_effect=core.ImportFailure('coverage failed')):
            with self.assertRaises(core.ImportFailure): self.install('--group', 'Anime')
        self.assertFalse(groups.config_path().exists())

    def test_nonexistent_selection_fails_without_metadata_write(self):
        with self.assertRaisesRegex(core.ImportFailure, 'no longer installed'):
            self.edit(action='group', slugs=['missing'], group='Anime')
        self.assertFalse(groups.config_path().exists())
