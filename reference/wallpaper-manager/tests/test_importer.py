"""Temporary-home regressions. No real theme changes or wallpaper playback."""
import importlib.util
from importlib.machinery import SourceFileLoader
import io
import json
import os
from pathlib import Path
import shutil
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import wallpaper_add as tool


def palette(path, accent='#6699cc'):
    values = {'background': '#101020', 'foreground': '#eeeeee', 'accent': accent}
    values.update({f'color{i}': '#223344' for i in range(16)})
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text('\n'.join(f'{key} = "{value}"' for key, value in values.items()) + '\n')


def package(files):
    def string(value):
        value = value.encode()
        return struct.pack('<I', len(value)) + value
    header = bytearray(string('PKGV0024') + struct.pack('<I', len(files)))
    data = bytearray()
    for name, contents in files.items():
        header += string(name) + struct.pack('<II', len(data), len(contents))
        data += contents
    return header + data


def texture():
    data = bytes([22, 88, 144, 255]) * 16
    return (b'TEXV0005\0TEXI0001\0' + struct.pack('<7i', 0, 0, 4, 4, 4, 4, 0)
            + b'TEXB0003\0' + struct.pack('<iiiiiiiii', 1, -1, 1, 4, 4, 0, len(data), len(data), 0)[:-4] + data)


class ImporterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='wallpaper-importer-test-')
        self.base = Path(self.temp.name)
        self.home = self.base / 'home'; self.home.mkdir()
        self.project = self.base / 'project'; self.project.mkdir()
        shutil.copytree(ROOT / 'vendor', self.project / 'vendor')
        self.source = self.base / 'Evening Image.png'
        Image.new('RGB', (128, 72), '#334466').save(self.source)
        self.calls = []
        env = dict(os.environ, HOME=str(self.home), XDG_CONFIG_HOME=str(self.home / '.config'),
                   XDG_DATA_HOME=str(self.home / '.local/share'), XDG_STATE_HOME=str(self.home / '.local/state'))
        self.patches = [patch.dict(os.environ, env), patch.object(tool, 'PROJECT', self.project),
                        patch.object(tool, 'run', side_effect=self.fake_run),
                        patch.object(tool, 'executable', side_effect=lambda name: name),
                        patch('sys.stdout', new=io.StringIO())]
        for p in self.patches: p.start()

    def tearDown(self):
        for p in reversed(self.patches): p.stop()
        self.temp.cleanup()

    def fake_run(self, command, log=None, timeout=300):
        args = list(map(str, command)); self.calls.append(args)
        if Path(args[0]).name == 'aether':
            for flag in ['--no-apply', '--no-zed', '--no-vscode', '--no-neovim']:
                self.assertIn(flag, args)
            palette(Path(args[args.index('--output') + 1]) / 'colors.toml')
        elif Path(args[0]).name == 'ffprobe':
            return json.dumps({'streams': [{'width': 128, 'height': 72, 'codec_name': 'h264', 'r_frame_rate': '30/1'}],
                               'format': {'duration': '6'}})
        elif Path(args[0]).name == 'ffmpeg':
            self.assertIn('1', args)
            Image.new('RGB', (128, 72), '#224466').save(args[-1])
        return ''

    def args(self, *extra):
        return tool.parser().parse_args([str(self.source), '--no-apply', *extra])

    def install(self, *extra):
        args = self.args(*extra); args.target = args.target or 'both'
        return tool.install(args)

    def records(self):
        return tool.read_json(tool.Locations().registry)['wallpapers']

    def test_blank_name_uses_filename_and_installs_both(self):
        record = self.install('--name', '')
        self.assertEqual(record['title'], 'Evening Image')
        self.assertEqual(record['targets'], ['omarchy', 'daemon-os'])
        self.assertTrue(Path(record['daemon_alias']).is_symlink())
        self.assertEqual(record['video'], None)
        self.assertEqual(self.records()[record['slug']]['installed_image'], record['installed_image'])
        self.assertTrue(Path(record['colors_toml']).is_file())

    def test_daemon_only_does_not_create_omarchy_theme(self):
        record = self.install('--target', 'daemon-os')
        self.assertFalse((tool.Locations().themes / record['slug']).exists())
        self.assertTrue(Path(record['daemon_alias']).is_symlink())
        self.assertTrue(Path(record['installed_theme']).is_relative_to(tool.Locations().library))

    def test_omarchy_only_has_no_daemon_alias(self):
        record = self.install('--target', 'omarchy')
        self.assertIsNone(record['daemon_alias'])
        self.assertFalse(tool.Locations().aliases.exists())

    def test_exact_video_pairing_and_bounded_poster_command(self):
        self.source = self.base / 'Actual Video.MP4'; self.source.write_bytes(b'original video payload')
        record = self.install('--name', 'Live Example')
        self.assertEqual(record['type'], 'video')
        self.assertEqual(Path(record['video']).read_bytes(), b'original video payload')
        self.assertEqual(Path(record['video']).name, 'live-example.mp4')
        command = next(c for c in self.calls if c[0] == 'ffmpeg')
        self.assertEqual(command[command.index('-threads') + 1], '1')
        self.assertEqual(command[command.index('-frames:v') + 1], '1')

    def test_static_video_poster_is_explicitly_static(self):
        self.source = self.base / 'Clip.mp4'; self.source.write_bytes(b'video')
        record = self.install('--mode', 'static')
        self.assertEqual(record['type'], 'static')
        self.assertIsNone(record['video'])

    def test_dry_run_does_not_generate_or_write(self):
        self.install('--dry-run')
        self.assertFalse(self.calls)
        self.assertFalse((self.project / 'data').exists())
        self.assertFalse(tool.Locations().registry.exists())

    def test_existing_name_rejected_before_generation(self):
        self.install()
        self.calls.clear()
        with self.assertRaisesRegex(tool.ImportFailure, 'already exists'):
            self.install()
        self.assertFalse(self.calls)

    def test_replacement_preserves_extra_files_and_backups(self):
        record = self.install()
        extra = Path(record['installed_theme']) / 'personal.conf'; extra.write_text('keep')
        colors = Path(record['colors_toml']); colors.write_text('original custom palette')
        self.install('--replace')
        self.assertEqual(extra.read_text(), 'keep')
        self.assertTrue(any(p.read_bytes() == b'original custom palette'
                            for p in (self.project / 'data/backups').glob('*/*') if p.is_file() and p.name.isdigit()))

    def test_rollback_restores_registry_and_overwritten_files(self):
        record = self.install()
        before = tool.Locations().registry.read_bytes()
        colors = Path(record['colors_toml']); colors.write_text('old palette')
        with patch.object(tool, 'backup_metadata', side_effect=tool.ImportFailure('backup failure')):
            with self.assertRaisesRegex(tool.ImportFailure, 'backup failure'):
                self.install('--replace')
        self.assertEqual(tool.Locations().registry.read_bytes(), before)
        self.assertEqual(colors.read_text(), 'old palette')

    def test_first_install_failure_removes_new_files(self):
        with patch.object(tool, 'backup_metadata', side_effect=tool.ImportFailure('backup failure')):
            with self.assertRaises(tool.ImportFailure): self.install()
        self.assertFalse(tool.Locations().registry.exists())
        self.assertFalse((tool.Locations().themes / 'evening-image').exists())
        self.assertFalse(list(tool.Locations().aliases.glob('*')))

    def test_invalid_registry_unchanged(self):
        path = tool.Locations().registry; path.parent.mkdir(parents=True); path.write_text('broken')
        with self.assertRaises(ValueError): self.install()
        self.assertEqual(path.read_text(), 'broken')
        self.assertFalse(self.calls)

    def test_explicit_palette_only_and_no_stale_aether_reuse(self):
        stale = self.home / '.config/aether/theme/colors.toml'; palette(stale, '#ff0000')
        record = self.install()
        self.assertEqual(record['accent'], '#6699cc')
        chosen = self.base / 'chosen.toml'; palette(chosen, '#ffcc00')
        self.calls.clear(); record = self.install('--name', 'Chosen', '--colors', str(chosen))
        self.assertEqual(record['accent'], '#ffcc00')
        self.assertFalse(any(c[0] == 'aether' for c in self.calls))

    def test_non_latin_name_stays_readable_with_safe_slug(self):
        record = self.install('--name', '夜の都市')
        self.assertEqual(record['title'], '夜の都市')
        self.assertRegex(record['slug'], r'^wallpaper-[a-f0-9]+$')

    def project_folder(self, kind, file, payload):
        folder = self.base / '1234567890'; folder.mkdir()
        (folder / file).write_bytes(payload)
        (folder / 'project.json').write_text(json.dumps({'title': 'Workshop Night', 'type': kind, 'file': file}))
        return folder

    def test_numeric_workshop_id_and_metadata_default_name(self):
        buffer = io.BytesIO(); Image.new('RGB', (64, 36), 'blue').save(buffer, format='PNG')
        folder = self.project_folder('scene', 'scene.pkg', package({'materials/full.png': buffer.getvalue()}))
        args = self.args('--mode', 'static', '--library-root', str(self.base)); args.source = folder.name; args.target = 'both'
        record = tool.install(args)
        self.assertEqual(record['title'], 'Workshop Night')
        self.assertEqual(record['type'], 'static')
        self.assertIn('Static scene/texture recovery', record['notes'][0])

    def test_tex_inside_pkg_decoded(self):
        folder = self.project_folder('scene', 'scene.pkg', package({'materials/full.tex': texture()}))
        self.source = folder
        record = self.install('--mode', 'static')
        self.assertEqual(record['size'], [4, 4])

    def test_scene_without_video_is_not_labelled_live(self):
        buffer = io.BytesIO(); Image.new('RGB', (64, 36), 'blue').save(buffer, format='PNG')
        self.source = self.project_folder('scene', 'scene.pkg', package({'full.png': buffer.getvalue()}))
        with self.assertRaisesRegex(tool.ImportFailure, 'no playable video'):
            self.install('--mode', 'video')
        self.assertFalse(tool.Locations().registry.exists())
        self.assertFalse(self.calls)

    def test_scene_static_fallback_requires_choice_in_auto_mode(self):
        self.source = self.project_folder('scene', 'scene.pkg', package({'note.txt': b'no movie'}))
        with self.assertRaisesRegex(tool.ImportFailure, 'Static scene recovery was not selected'):
            self.install()
        self.assertFalse(tool.Locations().registry.exists())

    def test_embedded_video_preserved(self):
        self.source = self.project_folder('scene', 'scene.pkg', package({'movie.mp4': b'actual embedded video'}))
        record = self.install('--mode', 'video')
        self.assertEqual(Path(record['video']).read_bytes(), b'actual embedded video')

    def test_package_traversal_is_rejected(self):
        self.source = self.project_folder('scene', 'scene.pkg', package({'../escape.png': b'bad'}))
        with self.assertRaisesRegex(tool.ImportFailure, 'outside'):
            self.install('--mode', 'static')
        self.assertFalse(tool.Locations().registry.exists())
        self.assertFalse(list((self.project / 'data/work').glob('*/escape.png')))

    def test_project_asset_cannot_escape_folder(self):
        folder = self.project_folder('video', 'clip.mp4', b'video')
        (folder / 'project.json').write_text(json.dumps({'type': 'video', 'file': '../outside.mp4'}))
        self.source = folder
        with self.assertRaisesRegex(tool.ImportFailure, 'outside'): self.install()

    def test_web_wallpaper_is_not_executed(self):
        self.source = self.project_folder('web', 'index.html', b'<script>bad()</script>')
        with self.assertRaisesRegex(tool.ImportFailure, 'not imported'): self.install()

    def test_activation_uses_native_commands_and_exact_installed_image(self):
        record = self.install()
        self.calls.clear()
        with patch.object(tool, 'detect_profile', return_value='omarchy'), patch.object(tool.shutil, 'which', return_value='omarchy-live-wallpaper'):
            self.assertTrue(tool.activate(record))
        self.assertEqual(self.calls[0], ['omarchy', 'theme', 'set', record['slug']])
        self.assertEqual(self.calls[1][-1], record['installed_image'])
        self.calls.clear()
        with patch.object(tool, 'detect_profile', return_value='daemon-os'), patch.object(tool.shutil, 'which', return_value='omarchy-live-wallpaper'):
            self.assertTrue(tool.activate(record))
        self.assertEqual(self.calls[0][:3], ['caelestia', 'wallpaper', '-f'])
        self.assertEqual(self.calls[0][3], record['daemon_alias'])

    def test_inactive_target_does_not_apply_to_wrong_desktop(self):
        record = self.install('--target', 'daemon-os'); self.calls.clear()
        with patch.object(tool, 'detect_profile', return_value='omarchy'):
            self.assertFalse(tool.activate(record))
        self.assertFalse(self.calls)

    def test_interactive_defaults_and_apply_choice(self):
        with patch('builtins.input', side_effect=['1', str(self.source), '', '', '3', 'n']), patch.object(tool.sys.stdin, 'isatty', return_value=True), patch.object(tool.os, 'nice'):
            self.assertEqual(tool.main([]), 0)
        self.assertEqual(self.records()['evening-image']['title'], 'Evening Image')

    def test_discovery_respects_targets_and_daemon_palette_resolves(self):
        daemon = self.install('--name', 'Daemon Example', '--target', 'daemon-os')
        self.install('--name', 'Omarchy Example', '--target', 'omarchy')
        self.install('--name', 'Both Example')
        source = (ROOT / 'integration/omarchy-caelestia-wallpaper-index').read_text()
        source = source.replace("Path('/usr/share/omarchy/themes')", repr(self.home / 'stock'))
        source = source.replace(repr(self.home / 'stock'), 'Path(' + repr(str(self.home / 'stock')) + ')')
        module = {'__name__': 'index_test'}
        exec(compile(source, 'index-test', 'exec'), module)
        module['main']()
        aliases = list(tool.Locations().aliases.iterdir())
        self.assertEqual(len(aliases), 2)
        self.assertFalse(any(p.name.startswith('omarchy-example-') for p in aliases))
        loader = SourceFileLoader('test_palette_bridge', str(ROOT / 'integration/omarchy-wallpaper-theme-sync'))
        spec = importlib.util.spec_from_loader(loader.name, loader); bridge = importlib.util.module_from_spec(spec); loader.exec_module(bridge)
        result = bridge.load_theme_colors_if_available(Path(daemon['daemon_alias']))
        self.assertEqual(result[2], 'daemon-example')
        self.assertEqual(result[1]['accent'], '6699cc')

    def test_configured_backup_manifests_are_updated_and_mirrored(self):
        paths = tool.Locations()
        config = paths.config / 'omarchy/cloud-sync.json'; config.parent.mkdir(parents=True)
        config.write_text(json.dumps({'folders': [
            {'enabled': True, 'path': str(self.home), 'type': 'directory'},
            {'enabled': True, 'path': str(self.project), 'type': 'directory'}]}))
        manifest = paths.config / 'omarchy/manifests/DAEMONOS_BACKUP_MANIFEST.json'
        manifest.parent.mkdir(); manifest.write_text(json.dumps({'items': [], 'keep': True}))
        markdown = manifest.with_suffix('.md'); markdown.write_text('# Existing backup\n')
        record = self.install()
        data = tool.read_json(manifest)
        self.assertTrue(data['keep'])
        self.assertEqual(data['wallpaper_importer']['last_import']['slug'], record['slug'])
        for source in [manifest, markdown]:
            self.assertEqual(source.read_bytes(), (self.home / 'Work' / source.name).read_bytes())

    def test_missing_backup_coverage_rolls_back_install(self):
        config = tool.Locations().config / 'omarchy/cloud-sync.json'
        config.parent.mkdir(parents=True); config.write_text('{"folders": []}')
        manifest = config.parent / 'manifests/DAEMONOS_BACKUP_MANIFEST.json'
        manifest.parent.mkdir(); manifest.write_text('{}')
        manifest.with_suffix('.md').write_text('# Backup manifest\n')
        with self.assertRaisesRegex(tool.ImportFailure, 'coverage is missing'):
            self.install()
        self.assertFalse(tool.Locations().registry.exists())
        self.assertFalse((tool.Locations().themes / 'evening-image').exists())

    def test_legacy_wallpaper_command_passes_source_name_and_target(self):
        loader = SourceFileLoader('legacy_import_proxy', str(ROOT / 'integration/omarchy-wallpaper-install'))
        spec = importlib.util.spec_from_loader(loader.name, loader); legacy = importlib.util.module_from_spec(spec); loader.exec_module(legacy)
        argv = ['wallpaper', '-w', str(self.source), '--target', 'daemon-os', '--name', 'My Theme', '--dry-run']
        with patch.object(sys, 'argv', argv), patch.object(legacy.subprocess, 'run') as runner:
            runner.return_value.returncode = 0
            with self.assertRaises(SystemExit) as result: legacy.main()
        self.assertEqual(result.exception.code, 0)
        command = runner.call_args.args[0]
        self.assertEqual(command[:2], [str(self.home / '.local/bin/wallpaper-add'), str(self.source)])
        self.assertIn('--no-apply', command)
        self.assertEqual(command[command.index('--name') + 1], 'My Theme')
        self.assertEqual(command[command.index('--target') + 1], 'daemon-os')

    def test_windows_texture_paths_are_normalized(self):
        self.source = self.project_folder('scene', 'scene.pkg', package({'materials\\full.tex': texture()}))
        record = self.install('--mode', 'static')
        self.assertEqual(record['size'], [4, 4])

    def remove(self, slug='evening-image', *extra):
        import wallpaper_remove
        args = tool.parser().parse_args(['--remove', slug, '--yes', *extra])
        return wallpaper_remove.remove(args)

    def test_removal_both_keeps_original_and_archives_installed_files(self):
        record = self.install()
        self.remove()
        self.assertTrue(self.source.is_file())
        self.assertFalse(Path(record['installed_theme']).exists())
        self.assertFalse(tool.Locations().library.joinpath(record['slug']).exists())
        self.assertFalse(Path(record['daemon_alias']).is_symlink())
        self.assertNotIn(record['slug'], self.records())
        journals = list((self.project / 'data/backups').glob('*-remove-*/journal.json'))
        entries = json.loads(journals[0].read_text())
        self.assertTrue(any(e['kind'] == 'moved' and Path(e['backup']).is_dir() for e in entries))

    def test_remove_omarchy_preserves_daemon_palette_and_alias(self):
        record = self.install()
        self.remove('evening-image', '--target', 'omarchy')
        saved = self.records()['evening-image']
        self.assertEqual(saved['targets'], ['daemon-os'])
        self.assertTrue(Path(saved['installed_image']).is_file())
        self.assertTrue(Path(saved['colors_toml']).is_file())
        self.assertTrue(Path(saved['daemon_alias']).is_file())
        self.assertFalse(Path(record['installed_theme']).exists())
        loader = SourceFileLoader('remove_palette_test', str(ROOT / 'integration/omarchy-wallpaper-theme-sync'))
        spec = importlib.util.spec_from_loader(loader.name, loader); bridge = importlib.util.module_from_spec(spec); loader.exec_module(bridge)
        self.assertEqual(bridge.load_theme_colors_if_available(Path(saved['daemon_alias']))[2], 'evening-image')

    def run_index(self):
        source = (ROOT / 'integration/omarchy-caelestia-wallpaper-index').read_text()
        source = source.replace("Path('/usr/share/omarchy/themes')", 'Path(' + repr(str(self.home / 'stock')) + ')')
        module = {'__name__': 'index_test'}; exec(compile(source, 'index-test', 'exec'), module); module['main']()

    def test_remove_daemon_preserves_omarchy_and_prevents_rediscovery(self):
        record = self.install()
        export = self.home / 'Wallpapers/wallpaper-engine/evening-image/backgrounds/full.png'
        export.parent.mkdir(parents=True); shutil.copy2(self.source, export)
        self.remove('evening-image', '--target', 'daemon-os')
        self.assertEqual(self.records()['evening-image']['targets'], ['omarchy'])
        self.assertTrue(Path(record['installed_image']).is_file())
        self.run_index()
        self.assertFalse(list(tool.Locations().aliases.iterdir()))
        self.assertTrue(self.source.is_file())

    def test_removal_refuses_active_theme_before_writes(self):
        import wallpaper_remove
        record = self.install(); before = tool.Locations().registry.read_bytes()
        with patch.object(wallpaper_remove, 'active_wallpaper', return_value=('omarchy', 'evening-image', Path(record['installed_image']))):
            with self.assertRaisesRegex(tool.ImportFailure, 'currently active'):
                self.remove()
        self.assertEqual(before, tool.Locations().registry.read_bytes())
        self.assertTrue(Path(record['daemon_alias']).is_file())

    def test_removal_backup_failure_restores_folders_and_alias(self):
        record = self.install(); before = tool.Locations().registry.read_bytes()
        with patch.object(tool, 'backup_metadata', side_effect=tool.ImportFailure('backup failure')):
            with self.assertRaisesRegex(tool.ImportFailure, 'backup failure'):
                self.remove()
        self.assertEqual(before, tool.Locations().registry.read_bytes())
        self.assertTrue(Path(record['installed_image']).is_file())
        self.assertTrue(Path(record['daemon_alias']).is_file())

    def test_removal_dry_run_and_confirmation_make_no_changes(self):
        import wallpaper_remove
        self.install(); before = tool.Locations().registry.read_bytes()
        self.remove('evening-image', '--dry-run')
        self.assertEqual(before, tool.Locations().registry.read_bytes())
        args = tool.parser().parse_args(['--remove', 'evening-image'])
        with self.assertRaisesRegex(tool.ImportFailure, 'not confirmed'):
            wallpaper_remove.remove(args)
        self.assertEqual(before, tool.Locations().registry.read_bytes())

    def test_removal_keeps_shared_live_video(self):
        self.source = self.base / 'video.mp4'; self.source.write_bytes(b'video')
        one = self.install('--name', 'One'); self.install('--name', 'Two')
        registry = tool.read_json(tool.Locations().registry)
        registry['wallpapers']['two']['video'] = one['video']
        tool.Locations().registry.write_text(json.dumps(registry))
        self.remove('one')
        self.assertTrue(Path(one['video']).is_file())
        self.assertTrue(self.source.is_file())

    def test_removal_archives_owned_live_video(self):
        self.source = self.base / 'video.mp4'; self.source.write_bytes(b'video')
        record = self.install('--name', 'Video')
        self.remove('video')
        self.assertFalse(Path(record['video']).exists())
        self.assertTrue(self.source.exists())

    def test_removal_protects_original_inside_theme_directory(self):
        record = self.install(); registry = tool.read_json(tool.Locations().registry)
        registry['wallpapers']['evening-image']['source_file'] = record['installed_image']
        tool.Locations().registry.write_text(json.dumps(registry))
        with self.assertRaisesRegex(tool.ImportFailure, 'original input is inside'):
            self.remove()
        self.assertTrue(Path(record['installed_image']).is_file())

    def test_removal_legacy_theme_and_video_are_discovered(self):
        import wallpaper_remove
        folder = tool.Locations().themes / 'old-custom'; palette(folder / 'colors.toml')
        (folder / 'backgrounds').mkdir(); shutil.copy2(self.source, folder / 'backgrounds/old.jpg')
        video = tool.Locations().videos / 'old.mp4'; video.parent.mkdir(parents=True); video.write_bytes(b'video')
        helper = self.base / 'helper'; helper.write_text('  old-custom) video_name="old.mp4" ;;')
        with patch.object(wallpaper_remove.shutil, 'which', return_value=str(helper)):
            record = wallpaper_remove.list_records()['old-custom']
        self.assertEqual(record['video'], str(video))
        self.assertEqual(record['type'], 'video')

    def test_readding_clears_daemon_discovery_exclusion(self):
        self.install(); self.remove()
        self.assertIn('evening-image', tool.read_json(tool.Locations().registry)['wallpaper_index_exclusions'])
        self.install()
        self.assertNotIn('evening-image', tool.read_json(tool.Locations().registry)['wallpaper_index_exclusions'])
        self.run_index()
        self.assertEqual(len(list(tool.Locations().aliases.iterdir())), 1)

    def test_packed_workshop_scene_file_resolves_scene_pkg(self):
        self.source = self.project_folder('scene', 'scene.pkg', package({'full.tex': texture()}))
        project = self.source / 'project.json'; data = json.loads(project.read_text()); data['file'] = 'scene.json'; project.write_text(json.dumps(data))
        self.assertEqual(self.install('--mode', 'static')['size'], [4, 4])

    def test_standalone_cloud_sync_without_optional_manifests_keeps_recovery(self):
        config = tool.Locations().config / 'omarchy/cloud-sync.json'
        config.parent.mkdir(parents=True); config.write_text('{"folders": []}')
        record = self.install('--target', 'omarchy')
        self.assertTrue(Path(record['installed_theme']).is_dir())
        self.assertTrue(list((self.project / 'data/backups').glob('*/journal.json')))


if __name__ == '__main__':
    unittest.main()
