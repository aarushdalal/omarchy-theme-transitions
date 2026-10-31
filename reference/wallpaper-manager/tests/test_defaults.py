"""Default-theme listing and persistent DaemonOS-only visibility rules."""
import io
import json
from pathlib import Path
import unittest
from unittest.mock import patch

from PIL import Image
import test_importer as fixture
import wallpaper_add as core
import wallpaper_remove as removal

ROOT = Path(__file__).resolve().parents[1]


class DefaultThemeTests(unittest.TestCase):
    setUp = fixture.ImporterTests.setUp
    tearDown = fixture.ImporterTests.tearDown
    fake_run = fixture.ImporterTests.fake_run
    args = fixture.ImporterTests.args
    install = fixture.ImporterTests.install
    records = fixture.ImporterTests.records

    def stock(self, name):
        path = self.home / 'stock' / name
        fixture.palette(path / 'colors.toml')
        (path / 'backgrounds').mkdir()
        Image.new('RGB', (12, 12), '#123456').save(path / 'backgrounds/full.png')
        return path

    def write_registry(self, **extra):
        paths = core.Locations(); paths.registry.parent.mkdir(parents=True, exist_ok=True)
        data = core.read_json(paths.registry) if paths.registry.exists() else {'version': 1, 'wallpapers': {}}
        data.update(extra); paths.registry.write_text(json.dumps(data))

    def index(self):
        text = (ROOT / 'integration/omarchy-caelestia-wallpaper-index').read_text()
        text = text.replace("Path('/usr/share/omarchy/themes')", 'Path(' + repr(str(self.home / 'stock')) + ')')
        module = {'__name__': 'index_test'}; exec(compile(text, 'index-test', 'exec'), module); module['main']()

    def test_manager_lists_custom_and_labelled_defaults_without_writes(self):
        self.install(); self.stock('solitude'); self.stock('osaka-jade')
        before = core.Locations().registry.read_bytes()
        output = io.StringIO()
        with patch.object(removal, 'STOCK_THEMES', self.home / 'stock'), patch('sys.stdout', output):
            removal.show_list()
        self.assertIn('Evening Image', output.getvalue()); self.assertIn('Solitude', output.getvalue())
        self.assertIn('Omarchy default', output.getvalue()); self.assertIn('1 custom themes; 2 Omarchy defaults.', output.getvalue())
        self.assertEqual(before, core.Locations().registry.read_bytes())

    def test_target_filter_and_hidden_labels_match_policy(self):
        for name in ['solitude', 'osaka-jade', 'vantablack', 'catppuccin']: self.stock(name)
        self.write_registry(daemonos_stock_theme_allowlist=['solitude', 'osaka-jade', 'vantablack'])
        with patch.object(removal, 'STOCK_THEMES', self.home / 'stock'):
            output = io.StringIO()
            with patch('sys.stdout', output):
                self.assertEqual(core.main(['--list', '--target', 'daemon-os']), 0)
            self.assertIn('Solitude', output.getvalue()); self.assertNotIn('Catppuccin', output.getvalue())
            output = io.StringIO()
            with patch('sys.stdout', output): removal.show_list()
            self.assertIn('hidden in DaemonOS', output.getvalue()); self.assertIn('Catppuccin', output.getvalue())

    def test_index_removes_only_other_defaults_and_blocks_future_defaults(self):
        for name in ['solitude', 'osaka-jade', 'vantablack', 'catppuccin']: self.stock(name)
        custom = self.install(); self.index()
        old_custom = Path(custom['daemon_alias']); self.assertTrue(old_custom.is_file())
        self.write_registry(daemonos_stock_theme_allowlist=['solitude', 'osaka-jade', 'vantablack'])
        self.index()
        aliases = list(core.Locations().aliases.iterdir())
        self.assertTrue(old_custom.is_file()); self.assertFalse(any(p.name.startswith('catppuccin-') for p in aliases))
        for name in ['solitude', 'osaka-jade', 'vantablack']:
            self.assertTrue(any(p.name.startswith(name + '-') for p in aliases))
        new = self.stock('future-stock-theme'); self.index()
        self.assertFalse(any(p.name.startswith('future-stock-theme-') for p in core.Locations().aliases.iterdir()))
        self.assertTrue((new / 'backgrounds/full.png').is_file())

    def test_no_allowlist_preserves_all_default_visibility_and_explicit_exclusion(self):
        self.stock('solitude'); self.stock('catppuccin')
        self.write_registry(wallpaper_index_exclusions={'catppuccin': []})
        self.index()
        aliases = list(core.Locations().aliases.iterdir()); self.assertEqual(len(aliases), 1)
        self.assertTrue(aliases[0].name.startswith('solitude-'))
        with patch.object(removal, 'STOCK_THEMES', self.home / 'stock'):
            records = removal.list_default_records()
        self.assertEqual(records['solitude']['targets'], ['omarchy', 'daemon-os'])
        self.assertEqual(records['catppuccin']['targets'], ['omarchy'])

    def test_invalid_allowlist_fails_before_index_changes(self):
        self.stock('solitude'); self.index()
        state = self.home / '.local/state/caelestia/wallpaper-index.json'; before = state.read_bytes()
        aliases = sorted(p.name for p in core.Locations().aliases.iterdir())
        self.write_registry(daemonos_stock_theme_allowlist='solitude')
        with self.assertRaisesRegex(ValueError, 'Invalid'): self.index()
        self.assertEqual(before, state.read_bytes()); self.assertEqual(aliases, sorted(p.name for p in core.Locations().aliases.iterdir()))
        with patch.object(removal, 'STOCK_THEMES', self.home / 'stock'):
            with self.assertRaises(core.ImportFailure): removal.list_default_records()

    def test_both_desktop_allowlists_hide_other_defaults_from_manager(self):
        for name in ['solitude', 'osaka-jade', 'vantablack', 'catppuccin']: self.stock(name)
        self.write_registry(daemonos_stock_theme_allowlist=['solitude', 'osaka-jade', 'vantablack'], omarchy_stock_theme_allowlist=['solitude', 'osaka-jade', 'vantablack'])
        with patch.object(removal, 'STOCK_THEMES', self.home / 'stock'):
            for target in [None, 'omarchy', 'daemon-os']:
                output = io.StringIO()
                with patch('sys.stdout', output): removal.show_list(target)
                self.assertNotIn('Catppuccin', output.getvalue()); self.assertIn('Solitude', output.getvalue())
                self.assertIn('3 Omarchy defaults.', output.getvalue())

    def test_default_listing_does_not_add_defaults_to_custom_remover(self):
        self.install(); stock = self.stock('solitude')
        with patch.object(removal, 'STOCK_THEMES', self.home / 'stock'):
            self.assertEqual(len(removal.list_records()), 1)
            with self.assertRaisesRegex(core.ImportFailure, 'exact custom theme'):
                removal.remove(core.parser().parse_args(['--remove', 'solitude', '--yes']))
        self.assertTrue((stock / 'colors.toml').is_file())
