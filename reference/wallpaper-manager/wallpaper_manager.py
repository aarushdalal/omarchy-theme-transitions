#!/usr/bin/python3
"""Quickshell manager backend. Structured requests, serial operations and recovery journals."""
from contextlib import redirect_stdout
from datetime import datetime
import io
import json
import os
from pathlib import Path
import subprocess
import sys

import wallpaper_add as core
import wallpaper_remove as removal
import wallpaper_groups as groups
from wallpaper_names import names, display_name


def emit(value):
    print(json.dumps(value, ensure_ascii=False), flush=True)


def snapshot():
    paths = core.Locations()
    records = removal.list_records(paths)
    records.update({s: r for s, r in removal.list_default_records(paths).items() if r['targets']})
    labels, data = names(), groups.load()
    active = paths.state / 'omarchy/current/theme.name'
    active = active.read_text().strip() if active.is_file() else ''
    rows = []
    for slug, record in records.items():
        folder = Path(record['installed_theme'])
        image = Path(record.get('installed_image') or folder / 'preview.jpg')
        # Small manager cards use existing posters; the native selector still uses originals.
        poster = next((folder / ('preview' + ext) for ext in ['.jpg', '.png', '.webp', '.jpeg'] if (folder / ('preview' + ext)).is_file()), None)
        if poster:
            image = poster
        if not image.is_file():
            image = next((p for p in sorted((folder / 'backgrounds').glob('*')) if p.suffix.lower() in core.IMAGES), image)
        rows.append(dict(slug=slug, title=labels.get(slug, record['title']), group=groups.group_for(slug, record, data),
                         type=record.get('type', 'static'), targets=record['targets'], preview=image.as_uri(),
                         active=slug == active, stock=record.get('origin') == 'omarchy-default'))
    rows.sort(key=lambda r: (r['title'].casefold(), r['slug']))
    import wallpaper_jobs
    return {'jobs': wallpaper_jobs.list_jobs(), 'items': rows, 'groups': sorted({r['group'] for r in rows if r['group']}, key=str.casefold),
            'first': data.get('first', {}), 'recovery': str(core.PROJECT / 'data/backups')}


def edit(request):
    records = {r['slug']: r for r in snapshot()['items']}
    data = groups.load()
    action = request['action']
    selected = request.get('slugs', [])
    if any(s not in records for s in selected):
        raise core.ImportFailure('A selected theme is no longer installed. Refresh the library.')
    group = groups.clean(request.get('group', ''))
    if action == 'group':
        if not selected:
            raise core.ImportFailure('Select at least one theme.')
        for slug in selected:
            data['assignments'][slug] = group
    elif action in {'rename-group', 'delete-group'}:
        old = request.get('old', '')
        if not old or (action == 'rename-group' and not group):
            raise core.ImportFailure('Choose a group and a non-empty new name.')
        group = '' if action == 'delete-group' else group
        for slug, record in records.items():
            if record['group'] == old:
                data['assignments'][slug] = group
        first = data.setdefault('first', {}).pop(old, None)
        if first and group:
            data['first'].setdefault(group, first)
    elif action == 'first':
        if len(selected) != 1 or not records[selected[0]]['group']:
            raise core.ImportFailure('Select one grouped theme to use as the group cover and first wallpaper.')
        data.setdefault('first', {})[records[selected[0]]['group']] = selected[0]
    elif action != 'rename-theme':
        raise core.ImportFailure('Unknown management action.')
    tx = core.Transaction(core.PROJECT / 'data/backups' / (datetime.now().strftime('%Y%m%d-%H%M%S-%f') + '-groups'))
    try:
        if action == 'rename-theme':
            if len(selected) != 1:
                raise core.ImportFailure('Select one theme to rename.')
            title = groups.clean(request.get('title', ''))
            if not title:
                raise core.ImportFailure('Enter a theme name.')
            labels = names(); labels[selected[0]] = title
            tx.text(groups.config_path().with_name('theme-names.json'), json.dumps(labels, indent=2, ensure_ascii=False) + '\n')
        else:
            tx.text(groups.config_path(), json.dumps(data, indent=2, ensure_ascii=False) + '\n')
        # Same manifest and coverage validation as imports, without changing media.
        record = next(iter(records.values())) if records else None
        if record:
            paths = core.Locations()
            folder = paths.themes / record['slug']
            core.backup_metadata(paths, dict(record, operation=action, installed_theme=str(paths.config / 'omarchy'), image=str(paths.config / 'omarchy')), tx)
    except BaseException:
        tx.rollback()
        raise
    return str(tx.directory)


def execute(request):
    action = request.get('action', 'snapshot')
    if action in {'draft-save', 'draft-load'}:
        import wallpaper_jobs
        return wallpaper_jobs.save_draft(request.get('batches', [])) if action == 'draft-save' else wallpaper_jobs.load_draft()
    if action == 'browser-places':
        from wallpaper_sources import mounted_places
        return {'places': mounted_places()}
    if action == 'discover-folders':
        from wallpaper_sources import scan_folders
        return scan_folders(request.get('paths', []), request.get('recursive') is True)
    if action == 'queue-import':
        import wallpaper_jobs
        result = wallpaper_jobs.submit(request)
        try:
            wallpaper_jobs.save_draft([])
        except OSError:
            result['message'] += ' The import started, but the saved draft could not be cleared.'
        return result
    if action == 'jobs':
        import wallpaper_jobs
        return {'jobs': wallpaper_jobs.list_jobs()}
    if action == 'job-details':
        import wallpaper_jobs
        job_id = str(request.get('id', ''))
        if not job_id or Path(job_id).name != job_id or job_id in {'.', '..'}:
            raise core.ImportFailure('Choose a valid import job.')
        job = wallpaper_jobs.root() / job_id
        data = core.read_json(job / 'status.json')
        details = (job / 'events.jsonl').read_text() if (job / 'events.jsonl').exists() else data.get('message', '')
        return {'job_details': details, 'message': data.get('message', '')}
    if action == 'snapshot':
        return snapshot()
    if action == 'discover':
        from wallpaper_bulk import discover
        values = request.get('paths', [])
        if not values or any(not isinstance(p, str) or not p.strip() for p in values):
            raise core.ImportFailure('Choose a wallpaper folder or files first.')
        for value in values:
            path = Path(value).expanduser()
            if path.is_dir() and path.resolve() in {Path('/'), Path.home().resolve()}:
                raise core.ImportFailure('Choose a specific wallpaper folder instead of your home folder or the whole computer.')
        sources, issues = discover(values, Path.home() / '.local/share/Steam/steamapps/workshop/content/431960', recursive=request.get('recursive') is True)
        existing = removal.list_records()
        origins = {str(Path(r['source_file']).resolve()) for r in existing.values() if r.get('source_file')}
        return {'candidates': [dict(source=str(s['path']), title=s['title'], group='',
                                    type=s['asset'].suffix.lower(), installed=core.slugify(s['title']) in existing or str(s['path']) in origins)
                               for s in sources], 'issues': issues,
                'scan_folders': [str(Path(v).expanduser().resolve()) for v in values if Path(v).expanduser().is_dir()],
                'recursive': request.get('recursive') is True}
    if action == 'apply':
        slug = request.get('slug')
        records = {r['slug']: r for r in snapshot()['items']}
        if slug not in records or 'omarchy' not in records[slug]['targets']:
            raise core.ImportFailure('Choose a theme installed for Omarchy.')
        core.run([core.executable('omarchy'), 'theme', 'set', slug], timeout=120)
        return {'message': 'Theme applied.'}
    if action in {'group', 'rename-group', 'delete-group', 'first', 'rename-theme'}:
        with core.import_lock():
            recovery = edit(request)
        return {'message': 'Library updated.', 'recovery': recovery}
    if action not in {'import', 'remove'}:
        raise core.ImportFailure('Unknown request.')
    if not request.get('confirmed'):
        raise core.ImportFailure('Review and confirm the selected operation in the manager.')
    target = request.get('target', 'both')
    if target not in {'both', 'omarchy', 'daemon-os'}:
        raise core.ImportFailure('Invalid desktop target.')
    items = request.get('items', [])
    results = []
    with core.import_lock():
        for index, item in enumerate(items):
            emit({'event': 'progress', 'current': index + 1, 'total': len(items), 'title': item.get('title') or item.get('slug')})
            args = core.parser().parse_args(['--target', target, '--non-interactive'])
            args.yes = True
            args.dry_run = bool(request.get('dry_run', False))
            output = io.StringIO()
            try:
                with redirect_stdout(output):
                    if action == 'import':
                        args.source, args.name = item['source'], item['title']
                        args.group = groups.clean(item.get('group', ''))
                        args.replace = bool(request.get('replace', False))
                        args.mode = request.get('mode', 'auto')
                        args.asset = item.get('asset') or None
                        args.allow_static_scenes = bool(request.get('allow_static_scenes', False))
                        record = core.install(args, False)
                        slug = record['slug'] if record else core.slugify(args.name)
                    else:
                        args.remove = item['slug']
                        removal.remove(args, False)
                        slug = args.remove
                results.append({'slug': slug, 'source': item.get('source'), 'title': item.get('title'), 'status': 'planned' if args.dry_run else 'done', 'details': output.getvalue()})
            except (ValueError, OSError, subprocess.SubprocessError) as error:
                message = str(error).replace('run interactively or select one with --asset.', "enter one of the filenames below in this source's Asset field and retry.")
                results.append({'slug': item.get('slug') or item.get('title'), 'source': item.get('source'), 'title': item.get('title'), 'status': 'failed', 'details': message})
            emit({'event': 'item', **results[-1]})
    from wallpaper_bulk import report
    with redirect_stdout(io.StringIO()):
        report(action, results, bool(request.get('dry_run', False)))
    return {'message': f'{sum(r["status"] != "failed" for r in results)}/{len(results)} completed.', 'results': results}


def main():
    if len(sys.argv) == 1 or sys.argv[1:] == ['--gui']:
        os.execvp('omarchy-shell', ['omarchy-shell', 'shell', 'summon', 'daemon0.wallpaper-manager', ''])
    if sys.argv[1] == '--cli':
        return core.main(sys.argv[2:])
    if sys.argv[1] != '--request':
        return core.main(sys.argv[1:])
    try:
        # The GUI streams one JSON line so large folder queues do not exceed
        # the operating system's limit on a single command-line argument.
        payload = sys.stdin.readline() if sys.argv[2] == '-' else sys.argv[2]
        request = json.loads(payload)
        os.nice(10)
        emit({'event': 'result', 'ok': True, **execute(request)})
        return 0
    except (ValueError, OSError, subprocess.SubprocessError, KeyError) as error:
        emit({'event': 'result', 'ok': False, 'message': str(error)})
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
