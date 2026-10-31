#!/usr/bin/python3
"""Import images, videos and Wallpaper Engine projects without running project code."""
import argparse
from contextlib import contextmanager
from datetime import datetime
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib
import unicodedata

from PIL import Image, ImageOps

PROJECT = Path(__file__).resolve().parent
IMAGES = {'.png', '.jpg', '.jpeg', '.webp', '.bmp', '.tiff', '.gif'}
VIDEOS = {'.mp4', '.mkv', '.webm', '.mov', '.m4v', '.avi'}
ENV = dict(os.environ, RAYON_NUM_THREADS='1', OMP_NUM_THREADS='1',
           OPENBLAS_NUM_THREADS='1', MAGICK_THREAD_LIMIT='1')


class ImportFailure(ValueError):
    pass


def read_json(path):
    return json.loads(Path(path).read_text())


def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def slugify(name):
    ascii_name = unicodedata.normalize('NFKD', name).encode('ascii', 'ignore').decode()
    slug = re.sub(r'[^a-z0-9]+', '-', ascii_name.lower()).strip('-')[:100].rstrip('-')
    if not slug:
        if any(c.isalnum() for c in name):
            return 'wallpaper-' + hashlib.sha256(name.encode()).hexdigest()[:10]
        raise ImportFailure('Use a theme name containing at least one letter or number.')
    return slug


def safe_child(root, relative):
    relative = str(relative).replace('\\', '/')
    if re.match(r'^[A-Za-z]:', relative):
        raise ImportFailure('A project references an absolute Windows path.')
    path = (Path(root) / relative).resolve()
    if not path.is_relative_to(Path(root).resolve()):
        raise ImportFailure('A project references a file outside its own folder.')
    return path


def run(command, log=None, timeout=300):
    result = subprocess.run([str(arg) for arg in command], env=ENV,
                            capture_output=True, text=True, timeout=timeout)
    if log:
        Path(log).write_text(result.stdout + result.stderr)
    if result.returncode:
        raise ImportFailure(f'{Path(str(command[0])).name} failed: '
                            + (result.stderr.strip()[-500:] or result.stdout.strip()[-500:]))
    return result.stdout


def executable(name):
    path = shutil.which(name)
    if not path:
        raise ImportFailure(f'{name} is required but is not installed.')
    return path


class Locations:
    def __init__(self):
        self.home = Path.home()
        self.config = Path(os.environ.get('XDG_CONFIG_HOME', self.home / '.config'))
        self.data = Path(os.environ.get('XDG_DATA_HOME', self.home / '.local/share'))
        self.state = Path(os.environ.get('XDG_STATE_HOME', self.home / '.local/state'))
        self.themes = self.config / 'omarchy/themes'
        self.library = self.data / 'omarchy/wallpapers/library'
        self.videos = self.data / 'omarchy/wallpapers/videos'
        self.aliases = self.data / 'caelestia/omarchy-wallpapers'
        self.registry = self.config / 'omarchy/wallpaper-library.json'


def resolve_source(value, library_root):
    value = value.strip()
    if len(value) > 1 and value[0] == value[-1] and value[0] in '\"\'':
        value = value[1:-1]
    path = Path(value).expanduser()
    if not path.exists() and value.isdigit():
        path = library_root / value
    path = path.resolve()
    if not path.exists():
        raise ImportFailure(f'Wallpaper not found: {path}')
    if path.is_file() and path.name == 'project.json':
        path = path.parent
    project = {}
    if path.is_dir():
        metadata = path / 'project.json'
        if not metadata.is_file():
            raise ImportFailure('Select one Workshop ID folder containing project.json, or a media/PKG file.')
        project = read_json(metadata)
        if not isinstance(project, dict):
            raise ImportFailure('project.json must contain an object.')
        if project.get('type', '').lower() in {'web', 'application'}:
            raise ImportFailure('Web/application wallpapers execute code and are not imported. Supply an image or video export.')
        asset = safe_child(path, project.get('file') or 'scene.pkg')
        if not asset.is_file() and project.get('type') == 'scene' and (path / 'scene.pkg').is_file():
            asset = path / 'scene.pkg'
        if not asset.is_file():
            raise ImportFailure(f'The project media/package is missing: {asset.name}')
    else:
        asset = path
        metadata = path.parent / 'project.json'
        if path.suffix.lower() in {'.pkg', '.tex'} and metadata.is_file():
            project = read_json(metadata)
            if not isinstance(project, dict):
                raise ImportFailure('project.json must contain an object.')
    if asset.suffix.lower() not in IMAGES | VIDEOS | {'.pkg', '.tex', '.json'}:
        raise ImportFailure('Supported inputs: images, videos, .pkg, .tex or a Workshop project folder.')
    if asset.suffix.lower() == '.json' and asset.name != 'scene.json':
        raise ImportFailure('Only a Wallpaper Engine scene.json may be used as a scene input.')
    title = project.get('title') or (path.name if path.is_dir() else path.stem)
    return {'path': path, 'asset': asset, 'project': project, 'title': str(title)}


def choose_asset(paths, interactive, requested=None):
    if requested:
        matches = [p for p in paths if str(p) == requested or p.name == requested
                   or p.as_posix().endswith('/' + requested)]
        if len(matches) != 1:
            raise ImportFailure('--asset must identify exactly one recovered media file.')
        return matches[0]
    if len(paths) == 1:
        return paths[0]
    if not interactive:
        raise ImportFailure('Multiple recovered media files; run interactively or select one with --asset.\n'
                            + '\n'.join(str(p) for p in paths))
    print('\nRecovered media (choose the actual wallpaper, not an effect layer):')
    for number, path in enumerate(paths, 1):
        detail = ''
        if path.suffix.lower() in IMAGES:
            with Image.open(path) as image:
                detail = f' — {image.width}×{image.height}'
        print(f'  {number}. {path.name}{detail}')
    while True:
        choice = input('Media number (or q to cancel): ').strip()
        if choice.lower() == 'q':
            raise ImportFailure('Cancelled.')
        if choice.isdigit() and 1 <= int(choice) <= len(paths):
            return paths[int(choice) - 1]


def scalar(value, default):
    if isinstance(value, dict):
        frames = value.get('animation', {}).get('c0', [])
        value = frames[0].get('value', default) if frames else value.get('value', default)
    return default if value is None else value


def vector(value, default):
    if isinstance(value, dict):
        value = value.get('value', default)
    return [float(v) for v in (value or default).split()]


def compose_scene(root, scene_path, output):
    """Recover the unanimated image layers; shaders/scripts are never evaluated."""
    scene = read_json(scene_path)
    layers = [o for o in scene.get('objects', []) if isinstance(o.get('image'), str)]
    projection = scene.get('general', {}).get('orthogonalprojection', {})
    if not layers or not projection.get('width') or not projection.get('height'):
        return False
    width, height = round(float(projection['width'])), round(float(projection['height']))
    if min(width, height) < 1 or width * height > 64_000_000:
        raise ImportFailure('Scene image dimensions are invalid or exceed 64 megapixels.')
    canvas = Image.new('RGBA', (width, height), (0, 0, 0, 255))
    painted = 0
    for layer in layers:
        if scalar(layer.get('visible'), True) is False:
            continue
        model = read_json(safe_child(root, layer['image']))
        material = read_json(safe_child(root, model['material']))
        texture = material['passes'][0]['textures'][0]
        candidates = [safe_child(root, 'materials/' + texture + ext)
                      for ext in ['.png', '.jpg', '.jpeg', '.bmp', '.webp']]
        path = next((p for p in candidates if p.is_file()), None)
        if not path:
            raise ImportFailure('A scene layer texture could not be recovered.')
        with Image.open(path) as original:
            image = original.convert('RGBA')
        size = vector(layer.get('size'), f'{image.width} {image.height}')
        scale = vector(layer.get('scale'), '1 1 1')
        w, h = round(size[0] * scale[0]), round(size[1] * scale[1])
        if min(w, h) <= 0 or w * h > 64_000_000:
            raise ImportFailure('A scene layer has unsupported dimensions or mirroring; choose a recovered image.')
        image = image.resize((w, h), Image.Resampling.LANCZOS)
        alpha = max(0, min(1, float(scalar(layer.get('alpha'), 1))))
        if alpha != 1:
            image.putalpha(image.getchannel('A').point(lambda a: round(a * alpha)))
        angle = vector(layer.get('angles'), '0 0 0')[2]
        if angle:
            image = image.rotate(math.degrees(angle), Image.Resampling.BICUBIC, expand=True)
        origin = vector(layer.get('origin'), f'{width / 2} {height / 2} 0')
        canvas.alpha_composite(image, (round(origin[0] - image.width / 2),
                                      round(height - origin[1] - image.height / 2)))
        painted += 1
    if not painted:
        return False
    canvas.convert('RGB').save(output, compress_level=3)
    return True


def prepare(source, work, args, interactive):
    asset = source['asset']
    notes = []
    if asset.suffix.lower() in {'.pkg', '.tex', '.json'}:
        recovered = work / 'extracted'
        recovered.mkdir()
        sys.path.insert(0, str(PROJECT / 'vendor'))
        if asset.suffix.lower() == '.pkg':
            from src.extractor import extract_package, parse_package
            info = parse_package(asset)
            if len(info.files) > 10000:
                raise ImportFailure('This package has too many files for a wallpaper import.')
            for entry in info.files:
                safe_child(recovered, entry.name)
                if entry.offset + entry.length > asset.stat().st_size - info.data_offset:
                    raise ImportFailure('The package contains an invalid file range.')
            log = []
            extract_package(asset, recovered, cleanup_non_images=False, log_callback=log.append)
            (work / 'extraction.log').write_text('\n'.join(log))
        elif asset.suffix.lower() == '.tex':
            from src.tex_parser import extract_tex_file
            extract_tex_file(asset, recovered)
        else:
            # A loose scene can reference neighbouring material/model files.
            recovered = asset.parent
        paths = sorted(p for p in recovered.rglob('*') if p.is_file()
                       and p.suffix.lower() in IMAGES | VIDEOS
                       and not p.name.lower().startswith(('preview.', 'thumbnail.')))
        videos = [p for p in paths if p.suffix.lower() in VIDEOS]
        if args.mode == 'video':
            if not videos:
                raise ImportFailure('This scene contains no playable video. Animated shaders/particles require a compatible renderer; no fake video was created. Use --mode static to explicitly recover a still.')
            notes.append('Recovered embedded video; this may be a layer rather than the complete scene.')
            asset = choose_asset(videos, interactive, args.asset)
        elif videos and args.mode == 'auto':
            if interactive:
                print('This package contains video media; scene effects are not rendered by extraction.')
            asset = choose_asset(videos, interactive, args.asset)
            notes.append('Recovered embedded media; scene effects are not rendered.')
        else:
            if args.mode == 'auto' and not getattr(args, 'allow_static_scenes', False):
                if not interactive or input('No complete video is available. Recover a STATIC image without animated effects? [y/N]: ').strip().lower() not in {'y', 'yes'}:
                    raise ImportFailure('Static scene recovery was not selected. No theme installed.')
            notes.append('Static scene/texture recovery only. Shaders, particles, audio and interaction are not reproduced.')
            images = [p for p in paths if p.suffix.lower() in IMAGES]
            scene = next(iter(recovered.rglob('scene.json')), None)
            composite = work / 'scene-still.png'
            composed = False
            if scene and not args.asset:
                try:
                    composed = compose_scene(recovered, scene, composite)
                except (ValueError, OSError, KeyError, IndexError, TypeError) as error:
                    print(f'Scene composition unavailable: {error}. Choose an extracted image instead.')
            if composed:
                asset = composite
            elif images:
                def area(path):
                    try:
                        with Image.open(path) as image:
                            return image.width * image.height
                    except OSError:
                        return 0
                images.sort(key=area, reverse=True)
                asset = choose_asset(images, interactive, args.asset)
            else:
                raise ImportFailure('No usable image was recovered from this package.')
    is_video = asset.suffix.lower() in VIDEOS
    if args.mode == 'video' and not is_video:
        raise ImportFailure('The selected file is an image, not a live video.')
    poster = work / 'wallpaper.png'
    video_info = None
    if is_video:
        video_info = json.loads(run([executable('ffprobe'), '-v', 'error', '-select_streams', 'v:0',
                                     '-show_entries', 'stream=codec_name,width,height,r_frame_rate:format=duration',
                                     '-of', 'json', asset]))
        if not video_info.get('streams'):
            raise ImportFailure('No video stream was found.')
        duration = float(video_info.get('format', {}).get('duration', 0))
        run([executable('ffmpeg'), '-v', 'error', '-nostdin', '-y', '-threads', '1',
             '-filter_threads', '1', '-hwaccel', 'auto', '-ss', str(min(duration / 2, 5)),
             '-i', asset, '-frames:v', '1', '-threads', '1', poster], work / 'poster.log')
        if args.mode == 'static':
            notes.append('Explicit static poster selected from a video; live playback was not installed.')
            is_video = False
    else:
        with Image.open(asset) as image:
            if getattr(image, 'is_animated', False) and args.mode != 'static':
                raise ImportFailure('Animated images need an MP4/WebM export for live playback, or --mode static for an explicit still.')
            image = ImageOps.exif_transpose(image)
            if asset.suffix.lower() == '.png' and not getattr(image, 'is_animated', False):
                shutil.copy2(asset, poster)
            else:
                image.convert('RGB').save(poster, compress_level=3)
    with Image.open(poster) as image:
        size = list(image.size)
        ImageOps.fit(image.convert('RGB'), (480, 270), method=Image.Resampling.LANCZOS).save(work / 'preview.jpg', quality=90)
    return poster, asset if is_video else None, size, notes, video_info


class Transaction:
    """Back up only files we write and restore them if installation fails."""
    def __init__(self, directory):
        self.directory = directory
        self.saved = {}
        self.created_dirs = set()

    def remember(self, path):
        path = Path(path)
        if path in self.saved:
            return
        record = {'path': str(path), 'kind': 'absent'}
        if path.is_symlink():
            record.update(kind='symlink', target=os.readlink(path))
        elif path.exists():
            if not path.is_file():
                raise ImportFailure(f'Expected a regular file: {path}')
            backup = self.directory / str(len(self.saved))
            backup.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, backup)
            record.update(kind='file', backup=str(backup))
        self.saved[path] = record
        self.directory.mkdir(parents=True, exist_ok=True)
        (self.directory / 'journal.json').write_text(json.dumps(list(self.saved.values()), indent=2) + '\n')

    def parents(self, path):
        p = path.parent
        while not p.exists():
            self.created_dirs.add(p)
            p = p.parent
        path.parent.mkdir(parents=True, exist_ok=True)

    def copy(self, source, dest):
        dest = Path(dest)
        self.remember(dest)
        self.parents(dest)
        temporary = dest.with_name(dest.name + f'.{os.getpid()}.tmp')
        try:
            shutil.copy2(source, temporary)
            temporary.replace(dest)
        finally:
            temporary.unlink(missing_ok=True)

    def text(self, dest, value):
        self.directory.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(dir=self.directory, mode='w', delete=False) as stream:
            stream.write(value)
            source = Path(stream.name)
        try:
            self.copy(source, dest)
        finally:
            source.unlink(missing_ok=True)

    def link(self, target, dest):
        self.remember(dest)
        self.parents(dest)
        temporary = dest.with_name(dest.name + f'.{os.getpid()}.tmp')
        try:
            temporary.symlink_to(target)
            temporary.replace(dest)
        finally:
            temporary.unlink(missing_ok=True)

    def retire(self, path):
        """Atomically move an installed file/folder into the recovery journal."""
        path = Path(path)
        if not path.exists() and not path.is_symlink():
            return
        if path in self.saved:
            raise ImportFailure('An installation path was unexpectedly scheduled twice.')
        self.directory.mkdir(parents=True, exist_ok=True)
        backup = self.directory / ('retired-' + str(len(self.saved)))
        record = {'path': str(path), 'kind': 'moved', 'backup': str(backup)}
        self.saved[path] = record
        (self.directory / 'journal.json').write_text(json.dumps(list(self.saved.values()), indent=2) + '\n')
        try:
            path.rename(backup)
        except OSError:
            del self.saved[path]
            (self.directory / 'journal.json').write_text(json.dumps(list(self.saved.values()), indent=2) + '\n')
            raise ImportFailure('Recovery must be on the same filesystem as the installed files; nothing was deleted.')

    def rollback(self):
        for path, record in reversed(list(self.saved.items())):
            if record['kind'] == 'moved':
                backup = Path(record['backup'])
                if backup.exists() or backup.is_symlink():
                    if path.exists() or path.is_symlink():
                        raise ImportFailure(f'Recovery collision at {path}; preserved backup: {backup}')
                    backup.rename(path)
                continue
            path.unlink(missing_ok=True)
            if record['kind'] == 'file':
                shutil.copy2(record['backup'], path)
            elif record['kind'] == 'symlink':
                path.symlink_to(record['target'])
        for path in sorted(self.created_dirs, key=lambda p: len(p.parts), reverse=True):
            try:
                path.rmdir()
            except OSError:
                pass


def covered(path, folders):
    path = Path(path).resolve()
    for folder in folders:
        if not folder.get('enabled') or folder.get('path') == 'system':
            continue
        root = Path(folder.get('path', '')).expanduser().resolve()
        if not path.is_relative_to(root):
            continue
        if folder.get('type') == 'directory':
            return True
        relative = path.relative_to(root)
        if relative.parts and relative.parts[0] in folder.get('subdirs', []) + folder.get('files', []):
            return True
    return False


def check_backup_coverage(paths, destinations):
    config = paths.config / 'omarchy/cloud-sync.json'
    if not config.exists() or not (paths.config / 'omarchy/manifests/DAEMONOS_BACKUP_MANIFEST.json').is_file() or not (paths.config / 'omarchy/manifests/DAEMONOS_BACKUP_MANIFEST.md').is_file():
        return
    folders = read_json(config).get('folders', [])
    for path in destinations:
        if not covered(path, folders):
            raise ImportFailure(f'Backup coverage is missing for {path}. Add it before importing.')


def backup_metadata(paths, record, tx):
    config = paths.config / 'omarchy/cloud-sync.json'
    if not config.exists() or not (paths.config / 'omarchy/manifests/DAEMONOS_BACKUP_MANIFEST.json').is_file() or not (paths.config / 'omarchy/manifests/DAEMONOS_BACKUP_MANIFEST.md').is_file():
        return  # Portable installs still retain a per-import rollback journal.
    destinations = [Path(record['installed_theme']), Path(record['image']), paths.registry, PROJECT]
    if record.get('video'):
        destinations.append(Path(record['video']))
    check_backup_coverage(paths, destinations)
    manifest = paths.config / 'omarchy/manifests/DAEMONOS_BACKUP_MANIFEST.json'
    markdown = manifest.with_suffix('.md')
    data = read_json(manifest)
    section = data.setdefault('wallpaper_importer', {})
    action = {
        'action': record.get('operation', 'import'),
        'slug': record['slug'], 'title': record['title'], 'type': record['type'],
        'targets': record['targets'], 'installed_theme': record['installed_theme'],
        'aether_no_apply': True, 'updated_at': datetime.now().astimezone().isoformat(timespec='seconds')}
    section.update(project=str(PROJECT), command='wallpaper-manager', last_action=action)
    if action['action'] == 'import':
        section['last_import'] = action
    text = markdown.read_text()
    begin, end = '<!-- wallpaper-importer-status -->', '<!-- /wallpaper-importer-status -->'
    note = (f'{begin}\n## Wallpaper importer\n\nCommand: `wallpaper-manager`. Latest {action["action"]}: '
            f'{record["title"]} (`{record["slug"]}`, {record["type"]}); targets: '
            f'{", ".join(record["targets"])}. Aether only exports colours. '
            'The importer retains a rollback journal and validates backup coverage.\n' + end)
    text = re.sub(re.escape(begin) + '.*?' + re.escape(end), lambda _: note, text, flags=re.S) if begin in text else text.rstrip() + '\n\n' + note + '\n'
    tx.text(manifest, json.dumps(data, indent=2) + '\n')
    tx.text(markdown, text)
    tx.copy(manifest, paths.home / 'Work' / manifest.name)
    tx.copy(markdown, paths.home / 'Work' / markdown.name)
    checker = shutil.which('daemonos-backup-check')
    if checker:
        run([checker, '--json'], tx.directory / 'backup-check.log', timeout=60)


def detect_profile():
    try:
        pids = subprocess.check_output(['pgrep', '-x', 'Hyprland'], text=True).split()
        if len(pids) == 1:
            args = Path('/proc') / pids[0] / 'cmdline'
            return 'daemon-os' if b'daemon-os/hyprland.lua' in args.read_bytes() else 'omarchy'
        if len(pids) > 1:
            return None
    except (OSError, subprocess.CalledProcessError):
        pass
    desktop = os.environ.get('XDG_CURRENT_DESKTOP', '').lower()
    if 'daemonos' in desktop:
        return 'daemon-os'
    if desktop == 'hyprland':
        return 'omarchy'
    return None


def activate(record):
    profile = detect_profile()
    if profile not in record['targets']:
        print('Installed for the selected desktop. Activate it after logging into that desktop; the current session was preserved.')
        return False
    if profile == 'daemon-os':
        run([executable('caelestia'), 'wallpaper', '-f', record['daemon_alias'], '--no-smart'], timeout=90)
    else:
        run([executable('omarchy'), 'theme', 'set', record['slug']], timeout=90)
    player = shutil.which('omarchy-live-wallpaper')
    if player:
        # The owned helper verifies decoding/resume and stops videos for static records.
        run([player, 'start', record['installed_image']], timeout=45)
    elif record['video']:
        raise ImportFailure('Theme installed, but the shared live player is missing. Install mpvpaper and the live-wallpaper integration before playing it.')
    print(f'Applied {record["title"]} on {profile}.')
    return True


def install(args, interactive=False):
    paths = Locations()
    source = resolve_source(args.source, Path(args.library_root).expanduser())
    name = args.name.strip() if args.name and args.name.strip() else source['title']
    slug = slugify(name)
    if (Path('/usr/share/omarchy/themes') / slug).exists():
        raise ImportFailure('That name belongs to a stock Omarchy theme. Choose a different custom name.')
    registry = read_json(paths.registry) if paths.registry.exists() else {'version': 1, 'wallpapers': {}}
    if not isinstance(registry.get('wallpapers'), dict):
        raise ImportFailure('The existing wallpaper registry is invalid.')
    previous = registry['wallpapers'].get(slug)
    if previous is not None and not isinstance(previous, dict):
        raise ImportFailure('The existing theme record is invalid.')
    import wallpaper_groups as grouping
    group = getattr(args, 'group', None)
    group = grouping.group_for(slug, previous) if group is None and previous else '' if group is None else group
    group = grouping.clean(group)
    targets = ['omarchy', 'daemon-os'] if args.target == 'both' else [args.target]
    canonical = paths.library / slug
    if (previous or canonical.exists() or (paths.themes / slug).exists()) and not args.replace:
        raise ImportFailure(f'Theme "{slug}" already exists. Choose another name or explicitly use --replace (backs up overwritten files).')
    if previous:
        targets = sorted(set(targets) | set(previous.get('targets', ['omarchy', 'daemon-os'])))
    elif args.replace and (paths.themes / slug).exists():
        targets = sorted(set(targets) | {'omarchy'})
    for folder in [canonical, paths.themes / slug]:
        if folder.resolve().is_relative_to(Path('/usr/share/omarchy')):
            raise ImportFailure('A destination points into the package-owned Omarchy directory.')
    print(f'\nTheme: {name}\nGroup: {group or "Ungrouped"}\nSource: {source["path"]}\nDesktop: {", ".join(targets)}')
    if args.dry_run:
        print('Dry run: would inspect/extract media, export Aether colours and install exact image/video pairings. No files or desktop settings changed.')
        return None
    if args.apply and detect_profile() in targets:
        executable('caelestia' if detect_profile() == 'daemon-os' else 'omarchy')
    stamp = datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    work = PROJECT / 'data/work' / (stamp + '-' + slug)
    work.mkdir(parents=True)
    poster, video, size, notes, video_info = prepare(source, work, args, interactive)
    if args.colors:
        colors = Path(args.colors).expanduser().resolve()
        if colors.is_dir():
            colors /= 'colors.toml'
    else:
        output = work / 'aether'
        run([executable('aether'), '--generate', poster, '--no-apply', '--no-zed', '--no-vscode', '--no-neovim', '--output', output], work / 'aether.log')
        colors = output / 'colors.toml'
    palette = tomllib.loads(colors.read_text())
    for key in ['background', 'foreground', 'accent'] + [f'color{i}' for i in range(16)]:
        if not re.fullmatch(r'#[a-fA-F0-9]{6}', palette.get(key, '')):
            raise ImportFailure(f'Invalid or missing palette colour: {key}')
    installed_theme = paths.themes / slug if 'omarchy' in targets else canonical
    installed_image = installed_theme / 'backgrounds' / (slug + '.png')
    canonical_image = canonical / 'backgrounds' / (slug + '.png')
    installed_video = paths.videos / (slug + video.suffix.lower()) if video else None
    alias = paths.aliases / (slug + '-' + hashlib.sha256(str(installed_image).encode()).hexdigest()[:12] + '-' + installed_image.name) if 'daemon-os' in targets else None
    record = dict(previous or {}, slug=slug, title=name, group=group, type='video' if video else 'static',
                  targets=targets, source_file=str(source['path']), source_sha256=digest(source['asset']),
                  source_kind='wallpaper-engine' if source['project'] or source['asset'].suffix.lower() in {'.pkg', '.tex'} else 'direct-media',
                  image=str(canonical_image), installed_image=str(installed_image), installed_theme=str(installed_theme),
                  colors_toml=str(installed_theme / 'colors.toml'), daemon_alias=str(alias) if alias else None,
                  video=str(installed_video) if installed_video else None, video_source=str(source['asset']) if video else None,
                  size=size, notes=notes, accent=palette['accent'], background=palette['background'], foreground=palette['foreground'])
    record['id'] = source['path'].name if source['path'].is_dir() and source['path'].name.isdigit() else 'import-' + record['source_sha256'][:16]
    if video_info:
        record['video_info'] = video_info
    # Other tools can update the shared library while Aether runs. Keep their records.
    latest = read_json(paths.registry) if paths.registry.exists() else {'version': 1, 'wallpapers': {}}
    if not isinstance(latest.get('wallpapers'), dict) or latest['wallpapers'].get(slug) != previous:
        raise ImportFailure('This theme record changed while preparing the import. Run again.')
    registry = latest
    tx = Transaction(PROJECT / 'data/backups' / (stamp + '-' + slug))
    try:
        destinations = [canonical] + ([installed_theme] if installed_theme != canonical else [])
        for folder in destinations:
            tx.copy(poster, folder / 'backgrounds' / (slug + '.png'))
            tx.copy(colors, folder / 'colors.toml')
            tx.copy(work / 'preview.jpg', folder / 'preview.jpg')
            tx.text(folder / '.aether-managed', '')
            tx.text(folder / 'wallpaper.json', json.dumps(record, indent=2, ensure_ascii=False) + '\n')
        if video:
            tx.copy(video, installed_video)
        if alias:
            tx.link(installed_image, alias)
        registry['wallpapers'][slug] = record
        if 'daemon-os' in targets:
            registry.get('wallpaper_index_exclusions', {}).pop(slug, None)
        tx.text(paths.registry, json.dumps(registry, indent=2, ensure_ascii=False) + '\n')
        group_data = grouping.load()
        group_data['assignments'][slug] = group
        tx.text(grouping.config_path(), json.dumps(group_data, indent=2, ensure_ascii=False) + '\n')
        backup_metadata(paths, record, tx)
    except BaseException:
        tx.rollback()
        raise
    print(f'Installed {record["type"]} theme: {slug}')
    for note in notes:
        print(note)
    print(f'Files: {installed_theme}\nRecovery: {tx.directory}')
    if args.apply:
        activate(record)
    else:
        print('Installed without applying. Select it later in your desktop wallpaper/theme picker.')
    return record


@contextmanager
def import_lock():
    directory = Locations().state / 'wallpaper-importer'
    directory.mkdir(parents=True, exist_ok=True)
    with (directory / 'import.lock').open('a') as stream:
        try:
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ImportFailure('Another wallpaper import is running. Try again after it finishes.')
        yield


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('source', nargs='?', help='Image/video, .pkg/.tex, Workshop folder or numeric Workshop ID')
    action = p.add_mutually_exclusive_group()
    action.add_argument('--remove', '--delete', nargs='?', const='__choose__', help='Remove an installed theme by exact name/slug, or choose interactively')
    action.add_argument('--bulk-add', nargs='*', help='Add multiple mixed images/videos/Workshop folders or scan folders')
    action.add_argument('--bulk-remove', nargs='*', help='Remove multiple custom theme names, or choose interactively; accepts all')
    action.add_argument('--list', action='store_true', help='List custom themes and Omarchy defaults; optionally filter with --target')
    p.add_argument('--yes', action='store_true', help='Confirm removal or the selected batch (preserves original downloads)')
    p.add_argument('--name', '-n', help='Theme name; blank uses filename/project title')
    p.add_argument('--group', help='Anime/type group; use an empty string to leave ungrouped. Also filters bulk removal.')
    p.add_argument('--target', choices=['omarchy', 'daemon-os', 'both'])
    mode = p.add_mutually_exclusive_group()
    mode.add_argument('--apply', action='store_true', help='Apply on the selected desktop if it is running')
    mode.add_argument('--no-apply', action='store_true', help='Install only')
    p.add_argument('--mode', choices=['auto', 'static', 'video'], default='auto')
    p.add_argument('--allow-static-scenes', action='store_true', help='Allow still recovery for scenes lacking video; direct videos remain live')
    p.add_argument('--asset', help='Choose a recovered package media filename/relative path')
    p.add_argument('--colors', help='Optional existing colors.toml (otherwise generate using Aether)')
    p.add_argument('--library-root', default=str(Path.home() / '.local/share/Steam/steamapps/workshop/content/431960'))
    p.add_argument('--replace', action='store_true', help='Back up/replace files for an existing name; retain other files and desktop bindings')
    p.add_argument('--dry-run', action='store_true', help='Inspect source/plan without extracting or writing files')
    p.add_argument('--non-interactive', action='store_true', help='Use supplied flags without questions')
    return p


def main(argv=None):
    args = parser().parse_args(argv)
    interactive = sys.stdin.isatty() and not args.non_interactive
    try:
        if args.source and (args.remove is not None or args.list or args.bulk_add is not None or args.bulk_remove is not None):
            raise ImportFailure('Choose adding a source, removal, or listing as a single action.')
        if interactive and not args.source and args.remove is None and not args.list and args.bulk_add is None and args.bulk_remove is None:
            while True:
                choice = input('Action: 1 Add, 2 Remove, 3 List, 4 Bulk add, 5 Bulk remove [1]: ').strip() or '1'
                if choice in {'1', '2', '3', '4', '5'}:
                    args.bulk_add = [] if choice == '4' else None
                    args.bulk_remove = [] if choice == '5' else None
                    args.remove = '__choose__' if choice == '2' else None
                    args.list = choice == '3'
                    break
        if args.bulk_add is not None or args.bulk_remove is not None:
            from wallpaper_bulk import add_batch, remove_batch
            operation = add_batch if args.bulk_add is not None else remove_batch
            try:
                os.nice(15)
            except OSError:
                pass
            if args.dry_run:
                return operation(args, interactive)
            with import_lock():
                return operation(args, interactive)
        if args.list or args.remove is not None:
            from wallpaper_remove import remove, show_list
            if args.list:
                show_list(args.target)
            elif args.dry_run:
                remove(args, interactive)
            else:
                with import_lock():
                    remove(args, interactive)
            return 0
        if not args.source:
            if not interactive:
                raise ImportFailure('Supply a source path or run wallpaper-add in a terminal.')
            args.source = input('Wallpaper image/video or Wallpaper Engine folder/ID: ').strip()
        source = resolve_source(args.source, Path(args.library_root).expanduser())
        if interactive:
            if args.name is None:
                args.name = input(f'Theme name [Enter = {source["title"]}]: ').strip() or source['title']
            if args.group is None:
                import wallpaper_groups as grouping
                args.group = grouping.prompt()
            if args.target is None:
                while True:
                    value = input('Desktop: 1 Omarchy, 2 DaemonOS, 3 Both [3]: ').strip() or '3'
                    if value in {'1', '2', '3'}:
                        args.target = {'1': 'omarchy', '2': 'daemon-os', '3': 'both'}[value]
                        break
            if not args.apply and not args.no_apply and not args.dry_run:
                args.apply = input('Apply on the selected desktop now? [y/N]: ').strip().lower() in {'y', 'yes'}
        args.target = args.target or 'both'
        try:
            os.nice(15)
        except OSError:
            pass
        if args.dry_run:
            install(args, interactive)
        else:
            with import_lock():
                install(args, interactive)
        return 0
    except (ImportFailure, OSError, ValueError, subprocess.SubprocessError) as error:
        print(f'Wallpaper manager: {error}', file=sys.stderr)
        return 1
    except (KeyboardInterrupt, EOFError):
        print('\nCancelled.', file=sys.stderr)
        return 130


if __name__ == '__main__':
    sys.modules['wallpaper_add'] = sys.modules[__name__]
    raise SystemExit(main())
