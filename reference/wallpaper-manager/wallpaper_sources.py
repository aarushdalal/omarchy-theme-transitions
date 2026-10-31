"""Read-only mounted places and folder-scoped GUI source discovery."""
import os
from pathlib import Path
import re

import wallpaper_add as core
import wallpaper_remove as removal
from wallpaper_bulk import discover


def mounted_places(mountinfo=None, home=None):
    home = Path(home or Path.home())
    rows = [{'name': 'Home', 'path': str(home), 'kind': 'home', 'read_only': False},
            {'name': 'File system', 'path': '/', 'kind': 'root', 'read_only': False}]
    if mountinfo is None:
        mountinfo = Path('/proc/self/mountinfo').read_text()
    seen = {str(home), '/'}
    excluded = ('/proc', '/sys', '/dev', '/boot', '/etc', '/usr', '/var', '/run/user')
    for line in mountinfo.splitlines():
        left, separator, right = line.partition(' - ')
        fields, details = left.split(), right.split()
        if not separator or len(fields) < 6 or len(details) < 2:
            continue
        decode = lambda value: re.sub(r'\\([0-7]{3})', lambda match: chr(int(match[1], 8)), value)
        target, source, filesystem = decode(fields[4]), decode(details[1]), details[0]
        if target in seen or target == '/home' or any(target == prefix or target.startswith(prefix + '/') for prefix in excluded):
            continue
        # Include mounted block devices at custom locations, user FUSE drives,
        # and network filesystems. Never enumerate a drive's contents here.
        if not (source.startswith('/dev/') or filesystem.startswith('fuse.') and filesystem not in {'fuse.portal', 'fuse.gvfsd-fuse'}
                or filesystem in {'nfs', 'nfs4', 'cifs', 'smb3'}):
            continue
        seen.add(target)
        rows.append({'name': Path(target).name or target, 'path': target, 'kind': 'drive',
                     'read_only': 'ro' in fields[5].split(',')})
    return rows[:2] + sorted(rows[2:], key=lambda row: (row['name'].casefold(), row['path']))


def scan_folders(values, recursive=False):
    if not isinstance(values, list) or not values or any(not isinstance(value, str) or not value.strip() for value in values):
        raise core.ImportFailure('Select at least one wallpaper folder.')
    folders, seen = [], set()
    for value in values:
        path = Path(value).expanduser().resolve()
        if path in {Path('/'), Path.home().resolve()}:
            raise core.ImportFailure('Choose specific wallpaper folders instead of your home folder or the whole computer.')
        if str(path) not in seen:
            seen.add(str(path))
            folders.append(path)
    existing = removal.list_records()
    origins = {str(Path(record['source_file']).resolve()) for record in existing.values() if record.get('source_file')}
    batches, claimed = [], set()
    # For overlapping parent/child selections, the most specific selected
    # folder owns a source. This keeps the chosen folders independent.
    for folder in sorted(folders, key=lambda path: len(path.parts), reverse=True):
        sources, issues = [], []
        if not folder.is_dir():
            issues.append({'source': str(folder), 'reason': 'This folder is no longer mounted or does not exist.'})
        elif not os.access(folder, os.R_OK | os.X_OK):
            issues.append({'source': str(folder), 'reason': 'This folder cannot be read. Check its permissions or mount it in Files.'})
        else:
            sources, issues = discover([str(folder)], Path.home() / '.local/share/Steam/steamapps/workshop/content/431960', recursive=recursive)
        candidates = []
        for source in sources:
            identity = str(source['asset'].resolve())
            if identity in claimed:
                continue
            claimed.add(identity)
            candidates.append({'source': str(source['path']), 'title': source['title'], 'group': '',
                               'type': source['asset'].suffix.lower(),
                               'installed': core.slugify(source['title']) in existing or str(source['path']) in origins})
        batches.append({'folder': str(folder), 'candidates': candidates, 'issues': issues})
    by_folder = {batch['folder']: batch for batch in batches}
    return {'folder_batches': [by_folder[str(folder)] for folder in folders], 'recursive': recursive}
