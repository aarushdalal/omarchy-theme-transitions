"""Serial mixed-media batches using the existing transactional import/removal paths."""
from argparse import Namespace
from contextlib import redirect_stdout
import io
from datetime import datetime
import json
import os
from pathlib import Path
import re
import shlex
import subprocess

import wallpaper_add as core
import wallpaper_remove as removal

ERRORS = (core.ImportFailure, OSError, ValueError, subprocess.SubprocessError)
SKIP_DIRS = {'ready', 'extracted', 'previews', '__pycache__', 'node_modules', 'data', '.git'}


def select_numbers(text, count):
    """Accept 1,3-5 or all,!2,!6-8. Empty input never means all."""
    selected = set()
    tokens = text.lower().replace(' ', ',').split(',')
    for token in filter(None, tokens):
        exclude = token.startswith('!')
        token = token.lstrip('!')
        if token == 'all':
            numbers = set(range(1, count + 1))
        elif re.fullmatch(r'\d+(?:-\d+)?', token):
            limits = [int(part) for part in token.split('-')]
            first, last = limits[0], limits[-1]
            if not 1 <= first <= last <= count:
                raise core.ImportFailure('Selection numbers are outside the displayed list.')
            numbers = set(range(first, last + 1))
        else:
            raise core.ImportFailure('Use numbers/ranges such as 1,3-5 or all,!2; q cancels.')
        selected = selected - numbers if exclude else selected | numbers
    if not selected:
        raise core.ImportFailure('No wallpapers selected.')
    return [n - 1 for n in sorted(selected)]


def choose(items, label):
    for number, text in enumerate(items, 1):
        print(f'{number}. {text}')
    while True:
        value = input(f'{label} (1,3-5 or all,!2; q cancels): ').strip()
        if value.lower() == 'q':
            raise core.ImportFailure('Cancelled.')
        try:
            return select_numbers(value, len(items))
        except core.ImportFailure as error:
            print(error)


def target_once(args, interactive):
    if args.target is None and interactive:
        while True:
            value = input('Desktop for the batch: 1 Omarchy, 2 DaemonOS, 3 Both [3]: ').strip() or '3'
            if value in {'1', '2', '3'}:
                args.target = {'1': 'omarchy', '2': 'daemon-os', '3': 'both'}[value]
                break
    args.target = args.target or 'both'


def confirm(args, interactive, action, count):
    if args.dry_run or args.yes:
        return
    if not interactive or input(f'{action} {count} wallpapers for {args.target}? [y/N]: ').strip().lower() not in {'y', 'yes'}:
        raise core.ImportFailure('Batch was not confirmed. Use --yes for a non-interactive batch.')


def input_paths():
    text = input('Files, Workshop IDs or a folder to scan (quote multiple paths with spaces): ').strip()
    # A single pasted path with spaces need not be quoted.
    return [text] if Path(text).expanduser().exists() else shlex.split(text)


def discover(values, library_root, recursive=True):
    """Treat each Workshop folder as one source, avoiding its preview/export copies."""
    candidates, issues, seen = [], [], set()

    def add(value):
        try:
            source = core.resolve_source(str(value), library_root)
            identity = str(source['asset'].resolve())
            if identity not in seen:
                seen.add(identity)
                candidates.append(source)
        except ERRORS as error:
            issues.append({'source': str(value), 'status': 'failed', 'reason': str(error)})

    for value in values:
        path = Path(value).expanduser()
        if path.is_dir() and not (path / 'project.json').is_file():
            root = path.resolve()
            for folder, dirs, names in os.walk(path, followlinks=False):
                current = Path(folder)
                dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS and not d.startswith('.') and not (current / d).is_symlink())
                if 'project.json' in names:
                    add(current)
                    dirs[:] = []
                    continue
                # An unpacked scene is a single project, not hundreds of layer images.
                if 'scene.json' in names:
                    add(current / 'scene.json')
                    dirs[:] = []
                    continue
                for name in sorted(names):
                    if name.lower().startswith(('preview.', 'thumbnail.')):
                        continue
                    if Path(name).suffix.lower() in core.IMAGES | core.VIDEOS | {'.pkg', '.tex'}:
                        asset = current / name
                        if asset.resolve().is_relative_to(root):
                            add(asset)
                if not recursive:
                    # Immediate Workshop projects remain one source each; ordinary
                    # child folders are entered only with explicit recursion.
                    for name in dirs:
                        child = current / name
                        if (child / 'project.json').is_file():
                            add(child)
                        elif (child / 'scene.json').is_file():
                            add(child / 'scene.json')
                    dirs[:] = []
        else:
            add(value)
    return candidates, issues


def report(action, results, dry_run):
    counts = {status: sum(r['status'] == status for r in results) for status in ['done', 'planned', 'skipped', 'failed']}
    print('\nBatch result: ' + ', '.join(f'{count} {status}' for status, count in counts.items() if count))
    for row in results:
        print(f'  {row["status"]}: {row.get("slug") or row.get("source")} - {row.get("reason", "")}')
    if not dry_run:
        folder = core.PROJECT / 'data/batches'
        folder.mkdir(parents=True, exist_ok=True)
        path = folder / (datetime.now().strftime('%Y%m%d-%H%M%S-%f') + '-' + action + '.json')
        path.write_text(json.dumps({'action': action, 'counts': counts, 'items': results}, indent=2, ensure_ascii=False) + '\n')
        print(f'Batch receipt: {path}')
    return 1 if counts['failed'] else 0


def add_batch(args, interactive=False):
    if args.name is not None:
        raise core.ImportFailure('Bulk themes use each source filename/project title. Use single import for --name.')
    values = args.bulk_add or (input_paths() if interactive else [])
    if not values:
        raise core.ImportFailure('Supply --bulk-add <files/folders/IDs...> or run it interactively.')
    sources, results = discover(values, Path(args.library_root).expanduser())
    if interactive and sources:
        selected = choose([f'{s["title"]} [{s["asset"].suffix.lower()}] — {s["path"]}' for s in sources], 'Add which wallpapers')
        sources = [sources[i] for i in selected]
    if not sources:
        return report('add', results or [{'source': ', '.join(values), 'status': 'failed', 'reason': 'No supported wallpapers found.'}], args.dry_run)
    target_once(args, interactive)
    existing = removal.load_registry(core.Locations())['wallpapers']
    installed_sources = {str(Path(record['source_file']).expanduser().resolve()) for record in existing.values()
                         if isinstance(record, dict) and record.get('source_file')}
    installed_ids = {str(r.get('id')) for r in existing.values() if isinstance(r, dict) and str(r.get('id', '')).isdigit()}
    installed_titles = {core.slugify(r['title']) for r in existing.values() if isinstance(r, dict) and r.get('title') and any(c.isalnum() for c in r['title'])}
    reserved, planned = set(), []
    paths = core.Locations()
    for source in sources:
        try:
            slug = core.slugify(source['title'])
        except core.ImportFailure as error:
            results.append({'source': str(source['path']), 'status': 'failed', 'reason': str(error)})
            continue
        origin = source['path'] if source['path'].is_dir() else source['path'].parent
        known_id = bool(source['project']) and origin.name in installed_ids
        reason = None
        if slug in reserved:
            reason = 'Another selected wallpaper has the same theme name; use a single import with --name.'
        elif not args.replace and (str(source['path']) in installed_sources or known_id or slug in installed_titles or slug in existing or (paths.themes / slug).exists() or (paths.library / slug).exists()):
            reason = 'Already installed or name in use; skipped. Use a new name or explicit --replace.'
        elif (Path('/usr/share/omarchy/themes') / slug).exists():
            reason = 'Stock Omarchy theme name is protected; use a single import with --name.'
        if reason:
            results.append({'source': str(source['path']), 'slug': slug, 'status': 'skipped', 'reason': reason})
        else:
            reserved.add(slug)
            planned.append(source)
    if not planned:
        return report('add', results, args.dry_run)
    print(f'Batch: {len(planned)} mixed-media imports for {args.target}; names come from individual sources.')
    import wallpaper_groups as grouping
    if interactive and getattr(args, 'group', None) is None:
        print('Use one group for this batch, or enter = to choose for each wallpaper.')
        args.group = input('Batch anime / type group [Enter = ungrouped; = = per item]: ').strip()
        args.group = None if args.group == '' else '' if args.group == '-' else args.group
    if interactive and not args.dry_run:
        if args.mode == 'auto' and not args.allow_static_scenes and any(s['asset'].suffix.lower() in {'.pkg', '.tex', '.json'} for s in planned):
            args.allow_static_scenes = input('Allow STATIC recovery for scenes without playable video? [y/N]: ').strip().lower() in {'y', 'yes'}
        if not args.apply and not args.no_apply:
            args.apply = input('Apply only the LAST successfully imported theme after the batch? [y/N]: ').strip().lower() in {'y', 'yes'}
    confirm(args, interactive, 'Add', len(planned))
    last = None
    for number, source in enumerate(planned, 1):
        print(f'\n[{number}/{len(planned)}] {source["title"]}')
        child = Namespace(**vars(args))
        child.source, child.name, child.apply = str(source['path']), source['title'], False
        if interactive and getattr(args, 'group', None) == '=':
            child.group = grouping.prompt()
        try:
            record = core.install(child, interactive=False)
            if record:
                last = record
            results.append({'source': str(source['path']), 'slug': core.slugify(source['title']), 'type': record['type'] if record else 'auto',
                            'status': 'planned' if args.dry_run else 'done', 'targets': args.target})
        except ERRORS as error:
            results.append({'source': str(source['path']), 'status': 'failed', 'reason': str(error)})
    if args.apply and last and not args.dry_run:
        try:
            core.activate(last)
        except ERRORS as error:
            results.append({'slug': last['slug'], 'status': 'failed', 'reason': 'Installed, but activation failed: ' + str(error)})
    return report('add', results, args.dry_run)


def remove_batch(args, interactive=False):
    records = removal.list_records()
    import wallpaper_groups as grouping
    if getattr(args, 'group', None) is not None:
        records = {s: r for s, r in records.items() if grouping.group_for(s, r) == args.group}
    choices = sorted(records, key=lambda slug: records[slug]['title'].casefold())
    keys = args.bulk_remove
    if not keys:
        if not interactive:
            raise core.ImportFailure('Supply --bulk-remove <theme-slugs...> or choose interactively.')
        if not choices:
            raise core.ImportFailure('No custom themes were found.')
        indices = choose([f'{records[s]["title"]} [{records[s]["type"]}; {", ".join(records[s]["targets"])}]' for s in choices], 'Remove which wallpapers')
        keys = [choices[i] for i in indices]
    elif keys == ['all']:
        keys = choices
    target_once(args, interactive)
    selected, results = [], []
    seen = set()
    for key in keys:
        matches = [s for s, r in records.items() if key == s or key.casefold() == r['title'].casefold()]
        if not matches:
            slug = core.slugify(key)
            matches = [slug] if slug in records else []
        if len(matches) != 1:
            results.append({'source': key, 'status': 'failed', 'reason': 'No unique installed custom theme with this name.'})
            continue
        slug = matches[0]
        if slug in seen:
            continue
        seen.add(slug)
        check = Namespace(**vars(args)); check.remove, check.dry_run, check.yes = slug, True, True
        try:
            with redirect_stdout(io.StringIO()):
                removal.remove(check, interactive=False)
            print(f'Ready: {slug} [{records[slug]["type"]}]')
            selected.append(slug)
        except ERRORS as error:
            results.append({'slug': slug, 'status': 'skipped', 'reason': str(error)})
            print(f'Skipping {slug}: {error}')
    if selected:
        print(f'\nBatch removal: {len(selected)} wallpapers for {args.target}: ' + ', '.join(selected))
        confirm(args, interactive, 'Remove', len(selected))
    for number, slug in enumerate(selected, 1):
        child = Namespace(**vars(args)); child.remove, child.yes = slug, True
        print(f'\n[{number}/{len(selected)}] {slug}')
        try:
            # Recheck active state and shared videos immediately before each mutation.
            removal.remove(child, interactive=False)
            results.append({'slug': slug, 'status': 'planned' if args.dry_run else 'done', 'targets': args.target})
        except ERRORS as error:
            results.append({'slug': slug, 'status': 'failed', 'reason': str(error)})
    return report('remove', results, args.dry_run)
