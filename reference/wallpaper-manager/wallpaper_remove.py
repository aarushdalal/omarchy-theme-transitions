"""Desktop-scoped removal with original-source protection and rollback."""
from datetime import datetime
from pathlib import Path
import json
import re
import shutil
import subprocess

from PIL import Image

import wallpaper_add as core

STOCK_THEMES = Path('/usr/share/omarchy/themes')


def load_registry(paths):
    data = core.read_json(paths.registry) if paths.registry.is_file() else {'version': 1, 'wallpapers': {}}
    if not isinstance(data.get('wallpapers'), dict):
        raise core.ImportFailure('The wallpaper registry is invalid.')
    return data


def legacy_videos(paths):
    helper = shutil.which('omarchy-live-wallpaper')
    if not helper:
        return {}
    text = Path(helper).read_text()
    mapping = dict(re.findall(r'^\s+([a-z0-9-]+)\)\s+video_name="([^"\n]+)"', text, re.M))
    return {slug: str(paths.videos / filename) for slug, filename in mapping.items()
            if Path(filename).name == filename and (paths.videos / filename).is_file()}


def list_records(paths=None):
    paths = paths or core.Locations()
    registry = load_registry(paths)
    records = {slug: dict(record) for slug, record in registry['wallpapers'].items()
               if isinstance(record, dict) and re.fullmatch(r'[a-z0-9]+(?:-[a-z0-9]+)*', slug)}
    stock = STOCK_THEMES
    videos = legacy_videos(paths)
    if paths.themes.is_dir():
        for folder in paths.themes.iterdir():
            if (folder / 'colors.toml').is_file() and not (stock / folder.name).exists():
                records.setdefault(folder.name, {'slug': folder.name, 'title': folder.name.replace('-', ' ').title(),
                                                'targets': ['omarchy', 'daemon-os'], 'type': 'video' if folder.name in videos else 'static',
                                                'video': videos.get(folder.name)})
    result = {}
    for slug, record in records.items():
        folder = paths.themes / slug
        if not folder.is_dir():
            folder = paths.library / slug
        if folder.resolve().is_relative_to(stock.resolve()):
            continue
        images = sorted(p for p in (folder / 'backgrounds').glob('*')
                        if p.is_file() and p.suffix.lower() in core.IMAGES)
        if not images:
            continue
        known = Path(record.get('installed_image', ''))
        image = known if known.is_file() and known.resolve().is_relative_to(folder.resolve()) else images[0]
        record.update(slug=slug, installed_theme=str(folder), installed_image=str(image),
                      image=record.get('image') or str(image), colors_toml=str(folder / 'colors.toml'))
        record.setdefault('title', slug.replace('-', ' ').title())
        record.setdefault('targets', ['omarchy', 'daemon-os'])
        record.setdefault('video', videos.get(slug))
        result[slug] = record
    return result


def list_default_records(paths=None):
    """Display packaged defaults without granting the custom remover ownership."""
    paths = paths or core.Locations()
    registry = load_registry(paths)
    allowed = registry.get('daemonos_stock_theme_allowlist')
    if allowed is not None and (not isinstance(allowed, list) or any(not isinstance(x, str) for x in allowed)):
        raise core.ImportFailure('The DaemonOS default-theme allowlist is invalid.')
    omarchy_allowed = registry.get('omarchy_stock_theme_allowlist')
    if omarchy_allowed is not None and (not isinstance(omarchy_allowed, list) or any(not isinstance(x, str) for x in omarchy_allowed)):
        raise core.ImportFailure('The Omarchy default-theme allowlist is invalid.')
    excluded = registry.get('wallpaper_index_exclusions', {})
    result = {}
    if not STOCK_THEMES.is_dir():
        return result
    for folder in sorted(STOCK_THEMES.iterdir()):
        if not folder.is_dir() or not (folder / 'colors.toml').is_file():
            continue
        targets = ['omarchy'] if omarchy_allowed is None or folder.name in omarchy_allowed else []
        if folder.name not in excluded and (allowed is None or folder.name in allowed):
            targets.append('daemon-os')
        result[folder.name] = {'slug': folder.name, 'title': folder.name.replace('-', ' ').title(),
                               'type': 'static', 'origin': 'omarchy-default', 'targets': targets,
                               'installed_theme': str(folder), 'colors_toml': str(folder / 'colors.toml')}
    return result


def show_list(target=None):
    custom = list_records()
    defaults = list_default_records()
    visible_custom = {slug: r for slug, r in custom.items() if target in {None, 'both'} or target in r['targets']}
    visible_defaults = {slug: r for slug, r in defaults.items() if r['targets'] and (target in {None, 'both'} or target in r['targets'])}
    records = dict(visible_custom, **visible_defaults)
    for slug, record in sorted(records.items(), key=lambda pair: pair[1]['title'].casefold()):
        kind = 'Omarchy default' if slug in visible_defaults else 'custom'
        visibility = ', '.join(record['targets'])
        if slug in visible_defaults and 'daemon-os' not in record['targets']:
            visibility += ' (hidden in DaemonOS)'
        print(f'{slug}  |  {record["title"]}  |  {kind}, {record["type"]}  |  {visibility}')
    print(f'{len(visible_custom)} custom themes; {len(visible_defaults)} Omarchy defaults.')


def active_wallpaper(paths):
    profile = core.detect_profile()
    current = paths.state / 'omarchy/current'
    name = (current / 'theme.name').read_text().strip() if (current / 'theme.name').is_file() else None
    pointer = current / 'background'
    if profile == 'daemon-os':
        state = paths.state / 'caelestia/wallpaper/path.txt'
        if state.is_file():
            pointer = Path(state.read_text().strip())
    return profile, name, pointer.resolve() if pointer.is_file() else None


def aliases_for(paths, slug, image):
    roots = [(paths.themes / slug).resolve(), (paths.library / slug).resolve()]
    result = []
    if not paths.aliases.is_dir():
        return result
    for path in paths.aliases.iterdir():
        exact_name = re.match(re.escape(slug) + r'-[a-f0-9]{12}-', path.name)
        if path.is_symlink() and (exact_name or any(path.resolve().is_relative_to(root) for root in roots)):
            result.append(path)
        elif path.is_file() and path.stem == slug:
            result.append(path)
    return result


def remove(args, interactive=False):
    paths = core.Locations()
    registry = load_registry(paths)
    records = list_records(paths)
    key = args.remove
    if key == '__choose__':
        if not interactive:
            raise core.ImportFailure('Supply --remove <theme-name>; use --list to see available themes.')
        choices = sorted(records, key=lambda slug: records[slug]['title'].casefold())
        if not choices:
            raise core.ImportFailure('No installed custom themes were found.')
        for number, slug in enumerate(choices, 1):
            print(f'{number}. {records[slug]["title"]} [{", ".join(records[slug]["targets"])}]')
        while True:
            value = input('Wallpaper number (or q to cancel): ').strip()
            if value.lower() == 'q':
                raise core.ImportFailure('Cancelled.')
            if value.isdigit() and 1 <= int(value) <= len(choices):
                key = choices[int(value) - 1]
                break
    matches = [slug for slug, record in records.items()
               if slug == key or record['title'].casefold() == key.casefold()]
    if not matches:
        slug = core.slugify(key)
        matches = [slug] if slug in records else []
    if len(matches) != 1:
        raise core.ImportFailure('Use an exact custom theme name/slug from --list.')
    slug = matches[0]
    record = records[slug]
    target = args.target
    if target is None and interactive:
        while True:
            choice = input('Remove from: 1 Omarchy, 2 DaemonOS, 3 Both [3]: ').strip() or '3'
            if choice in {'1', '2', '3'}:
                target = {'1': 'omarchy', '2': 'daemon-os', '3': 'both'}[choice]
                break
    requested = {'omarchy', 'daemon-os'} if target in {None, 'both'} else {target}
    removing = set(record['targets']) & requested
    remaining = set(record['targets']) - removing
    if not removing:
        raise core.ImportFailure('This theme is not installed for the selected desktop.')
    source = Path(record['source_file']).resolve() if record.get('source_file') else None
    image = Path(record['installed_image'])
    aliases = aliases_for(paths, slug, image)
    moving = []
    if 'omarchy' in removing:
        moving.append(paths.themes / slug)
    export = paths.home / 'Wallpapers/wallpaper-engine' / slug
    if 'daemon-os' in removing and export.exists() and not (source and source.is_relative_to(export.resolve())):
        moving.append(export)
    if not remaining:
        moving.append(paths.library / slug)
    video = Path(record['video']) if record.get('video') else None
    if not remaining and video and video.resolve().is_relative_to(paths.videos.resolve()) and video.resolve() != source:
        shared = any(other['slug'] != slug and other.get('video') and Path(other['video']).resolve() == video.resolve()
                     for other in records.values())
        if not shared:
            moving.append(video)
    moving = [p for p in moving if p.exists() or p.is_symlink()]
    for path in moving:
        if source and (source == path.resolve() or (path.is_dir() and source.is_relative_to(path.resolve()))):
            raise core.ImportFailure('The original input is inside an installed folder. Move that original outside the theme folder before removal.')
    profile, active_slug, active_image = active_wallpaper(paths)
    if (profile in removing and active_slug == slug) or (active_image and any(active_image.is_relative_to(p.resolve()) for p in moving if p.is_dir())):
        raise core.ImportFailure('This wallpaper is currently active or supplies the active image. Select another wallpaper before removing it.')
    env_file = paths.state / 'omarchy/live-wallpaper.env'
    if video and video in moving and env_file.is_file() and str(video) in env_file.read_text():
        status = subprocess.run(['systemctl', '--user', 'is-active', '--quiet', 'omarchy-live-wallpaper.service'], capture_output=True)
        if status.returncode == 0:
            raise core.ImportFailure('This video is playing. Select another wallpaper or stop the live player before removing it.')
    print(f'Remove {record["title"]} from {", ".join(sorted(removing))}.')
    print('Original input/download files are preserved. Installed files move into a recovery backup.')
    if remaining:
        print('Keeping the theme for: ' + ', '.join(sorted(remaining)))
    if args.dry_run:
        for path in moving + aliases:
            print('Would retire: ' + str(path))
        return
    if not args.yes:
        if not interactive or input('Continue with removal? [y/N]: ').strip().lower() not in {'y', 'yes'}:
            raise core.ImportFailure('Removal was not confirmed. Use --yes for an explicit non-interactive removal.')
    stamp = datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    tx = core.Transaction(core.PROJECT / 'data/backups' / (stamp + '-remove-' + slug))
    updated = dict(record, operation='remove', targets=sorted(remaining))
    try:
        new_alias = None
        if remaining == {'daemon-os'} and 'omarchy' in removing:
            # The DaemonOS image/palette must survive retiring the Omarchy folder.
            canonical = paths.library / slug
            promoted_image = canonical / 'backgrounds' / image.name
            tx.copy(image, promoted_image)
            tx.copy(record['colors_toml'], canonical / 'colors.toml')
            preview = Path(record['installed_theme']) / 'preview.jpg'
            if preview.is_file():
                tx.copy(preview, canonical / 'preview.jpg')
            new_alias = paths.aliases / (slug + '-' + core.hashlib.sha256(str(promoted_image).encode()).hexdigest()[:12] + '-' + image.name)
            tx.link(promoted_image, new_alias)
            updated.update(installed_theme=str(canonical), installed_image=str(promoted_image), image=str(promoted_image),
                           colors_toml=str(canonical / 'colors.toml'), daemon_alias=str(new_alias))
        if 'daemon-os' not in remaining:
            updated['daemon_alias'] = None
        for path in aliases:
            if path != new_alias:
                tx.retire(path)
        for path in moving:
            tx.retire(path)
        if remaining:
            registry['wallpapers'][slug] = {k: v for k, v in updated.items() if k != 'operation'}
            tx.text(Path(updated['installed_theme']) / 'wallpaper.json', json.dumps(registry['wallpapers'][slug], indent=2) + '\n')
        else:
            registry['wallpapers'].pop(slug, None)
            import wallpaper_groups as grouping
            group_data = grouping.load()
            group_data['assignments'].pop(slug, None)
            group_data['first'] = {g: s for g, s in group_data.get('first', {}).items() if s != slug}
            tx.text(grouping.config_path(), json.dumps(group_data, indent=2, ensure_ascii=False) + '\n')
        if 'daemon-os' not in remaining:
            excluded = {str(image.resolve()), str(Path(record['image']).resolve())}
            if source and source.is_file() and source.suffix.lower() in core.IMAGES:
                excluded.add(str(source))
            # Keep source pictures in place, but don't rediscover them as installed themes.
            registry.setdefault('wallpaper_index_exclusions', {})[slug] = sorted(excluded)
        tx.text(paths.registry, json.dumps(registry, indent=2, ensure_ascii=False) + '\n')
        core.backup_metadata(paths, updated, tx)
    except BaseException:
        tx.rollback()
        raise
    print(f'Removed from the selected desktop(s). Recovery: {tx.directory}')
