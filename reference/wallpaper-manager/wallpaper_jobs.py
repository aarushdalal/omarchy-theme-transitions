"""Durable, serial background wallpaper batches, independent of the shell window."""
from datetime import datetime
from pathlib import Path
import fcntl
import json
import os
import subprocess
import sys
import time
import uuid

import wallpaper_add as core
import wallpaper_groups as groups


def root():
    return core.PROJECT / 'data/jobs'


def draft_path():
    return core.PROJECT / 'data/pending-draft.json'


def save_draft(batches):
    if not isinstance(batches, list):
        raise core.ImportFailure('Invalid folder draft.')
    atomic(draft_path(), {'batches': batches})
    return {'draft_saved': True}


def load_draft():
    path = draft_path()
    return {'draft_batches': json.loads(path.read_text()).get('batches', []) if path.is_file() else []}


def preflight(batches):
    paths = core.Locations()
    destinations = [core.PROJECT, paths.registry, paths.library / '__import_check__']
    if any(batch['target'] in {'omarchy', 'both'} for batch in batches):
        destinations.append(paths.themes / '__import_check__')
    if any(batch.get('mode') == 'video' or any(Path(item['source']).suffix.lower() not in core.IMAGES for item in batch['items']) for batch in batches):
        destinations.append(paths.videos / '__import_check__')
    core.check_backup_coverage(paths, destinations)


def atomic(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + '.' + str(os.getpid()) + '.tmp')
    temporary.write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n')
    temporary.replace(path)


def summary(path):
    data = json.loads(path.read_text())
    return {k: v for k, v in data.items() if k not in {'results'}}


def list_jobs():
    folder = root()
    if not folder.exists(): return []
    jobs = []
    for path in sorted(folder.glob('*/status.json'), reverse=True):
        try:
            state = summary(path)
            if state['state'] == 'running' and state.get('pid'):
                try: os.kill(state['pid'], 0)
                except ProcessLookupError:
                    state.update(state='interrupted', message='Import was interrupted. Completed themes are kept; review and retry the remaining files.')
                    atomic(path, state)
            jobs.append(state)
        except (OSError, ValueError, KeyError): continue
    active = sorted([j for j in jobs if j['state'] in {'pending', 'running'}],
                    key=lambda j: (j['state'] != 'running', j['id']))
    return active + [j for j in jobs if j['state'] not in {'pending', 'running'}][:4]


def validate(request):
    if not request.get('confirmed'):
        raise core.ImportFailure('Review and confirm the queued batches first.')
    batches = request.get('batches')
    if not isinstance(batches, list) or not batches:
        raise core.ImportFailure('Add at least one batch to the queue.')
    result, seen = [], set()
    for batch in batches:
        group = groups.clean(batch.get('group', ''))
        target = batch.get('target', 'both')
        if target not in {'both', 'omarchy', 'daemon-os'}:
            raise core.ImportFailure('Choose a valid desktop for each batch.')
        if batch.get('mode', 'auto') not in {'auto', 'static', 'video'}:
            raise core.ImportFailure('Choose automatic, static or video mode for each batch.')
        items = batch.get('items', [])
        if not items: raise core.ImportFailure('A queued batch has no wallpapers.')
        checked = []
        for item in items:
            if not isinstance(item.get('source'), str) or not item['source'].strip() or not str(item.get('title', '')).strip():
                raise core.ImportFailure('Each queued wallpaper needs a source and name.')
            identity = str(Path(item['source']).expanduser().resolve())
            if identity in seen: raise core.ImportFailure('The same source is queued more than once: ' + item['source'])
            seen.add(identity)
            checked.append(dict(item, group=group))
        result.append(dict(batch, group=group, target=target, items=checked))
    return result


def job_directory(job_id):
    job_id = str(job_id)
    if not job_id or Path(job_id).name != job_id or job_id in {'.', '..'}:
        raise core.ImportFailure('Choose a valid import job.')
    directory = root() / job_id
    if not directory.is_dir() or directory.resolve().parent != root().resolve():
        raise core.ImportFailure('That import job is no longer available.')
    return directory


def receipts(directory, state):
    path = directory / 'events.jsonl'
    if not path.is_file():
        return state.get('results', [])
    result = []
    for line in path.read_text().splitlines():
        try:
            result.append(json.loads(line))
        except ValueError:
            continue  # A process interruption can leave its final line partial.
    return result


def item_key(item):
    return (item.get('source'), item.get('title'))


def retry_plan(job_id):
    import wallpaper_remove as removal
    directory = job_directory(job_id)
    list_jobs()  # Refresh dead-worker states before checking retry eligibility.
    state = core.read_json(directory / 'status.json')
    if state['state'] in {'pending', 'running'}:
        raise core.ImportFailure('Wait for this import to finish before retrying failed files.')
    # Successful descendant retries remain successes even when the original
    # historical receipt still records its earlier failures.
    all_states = []
    for path in root().glob('*/status.json'):
        try:
            all_states.append(summary(path))
        except (OSError, ValueError):
            continue
    by_id = {entry['id']: entry for entry in all_states}
    ancestor, seen = str(job_id), set()
    while by_id.get(ancestor, {}).get('retry_of') in by_id and ancestor not in seen:
        seen.add(ancestor); ancestor = by_id[ancestor]['retry_of']
    descendants, recovered = {ancestor}, set()
    changed = True
    while changed:
        changed = False
        for child in all_states:
            if child.get('retry_of') in descendants and child['id'] not in descendants:
                if child['state'] in {'pending', 'running'}:
                    raise core.ImportFailure('A retry for this run is already queued or running.')
                descendants.add(child['id']); changed = True
                recovered.update(item_key(event) for event in receipts(root() / child['id'], child) if event.get('status') in {'done', 'planned'})
    latest = {item_key(event): event.get('status') for event in receipts(directory, state)}
    records = removal.load_registry(core.Locations())['wallpapers']
    batches, skipped, failures = [], 0, 0
    request = core.read_json(directory / 'request.json')
    for batch in request['batches']:
        items = []
        for item in batch['items']:
            key = item_key(item)
            if latest.get(key) in {'done', 'planned'} or state['state'] == 'completed':
                continue
            failures += 1
            record = records.get(core.slugify(item['title']), {})
            image = record.get('installed_image') or record.get('image')
            targets = {'omarchy', 'daemon-os'} if batch['target'] == 'both' else {batch['target']}
            installed = False
            if not batch.get('replace') and targets.issubset(set(record.get('targets', []))) and image and Path(image).is_file():
                source = Path(item['source']).expanduser()
                installed = bool(record.get('source_file') and Path(record['source_file']).expanduser().resolve() == source.resolve())
                if not installed and record.get('source_sha256') and source.is_file():
                    # Moving a source to another drive does not make an already
                    # imported wallpaper a failed import again.
                    try:
                        installed = core.digest(source) == record['source_sha256']
                    except OSError:
                        pass
            if key in recovered or installed:
                skipped += 1
            else:
                items.append(item)
        if items:
            batches.append(dict(batch, items=items))
    count = sum(len(batch['items']) for batch in batches)
    return {'id': str(job_id), 'count': count, 'failed': failures, 'skipped': skipped, 'batches': batches}


def retry_preview(job_id):
    plan = retry_plan(job_id)
    message = (f'{plan["count"]} failed or unfinished wallpapers are ready to retry. '
               f'{plan["skipped"]} already recovered files will be left untouched.' if plan['count'] else
               'There are no failed files left to retry. Any earlier failures have already been recovered.')
    return {'retry_preview': plan, 'message': message}


def retry_failed(job_id, confirmed=False):
    if not confirmed:
        raise core.ImportFailure('Review and confirm the failed-file retry first.')
    job_directory(job_id)
    with (root() / 'retry-submit.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise core.ImportFailure('A retry for this run is already being prepared.')
        plan = retry_plan(job_id)
        if not plan['count']:
            return {'retry_empty': True, 'jobs': list_jobs(), 'message': 'There are no failed files left to retry. Your current queue is unchanged.'}
        result = submit({'batches': plan['batches'], 'confirmed': True}, retry_of=str(job_id))
        result['message'] = f'{plan["count"]} failed or unfinished wallpapers queued for retry. {plan["skipped"]} already recovered files skipped. You can close this window.'
        return result


def submit(request, *, retry_of=None):
    batches = validate(request)
    try:
        preflight(batches)
    except core.ImportFailure:
        # Retain an exact, unsubmitted draft even for an older loaded GUI.
        if retry_of is None:
            save_draft(batches)
        raise
    folder = root(); folder.mkdir(parents=True, exist_ok=True)
    job_id = datetime.now().strftime('%Y%m%d-%H%M%S-%f') + '-' + uuid.uuid4().hex[:6]
    directory = folder / job_id; directory.mkdir()
    total = sum(len(b['items']) for b in batches)
    status = {'id': job_id, 'state': 'pending', 'total': total, 'completed': 0, 'done': 0, 'failed': 0,
              'batch': 0, 'batches': len(batches), 'message': 'Queued for background import.', 'folder': str(directory)}
    if retry_of is not None:
        status['retry_of'] = retry_of
    atomic(directory / 'request.json', {'batches': batches, **({'retry_of': retry_of} if retry_of is not None else {})})
    atomic(directory / 'status.json', status)
    try:
        with (folder / 'worker.log').open('a') as log:
            subprocess.Popen([sys.executable, str(Path(__file__).resolve()), '--worker', str(folder)],
                             stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True)
    except OSError:
        status.update(state='failed', message='Could not start the background importer.')
        atomic(directory / 'status.json', status)
        raise
    return {'message': f'{len(batches)} batches ({total} wallpapers) queued. You can close this window.',
            'queued_job': job_id, 'jobs': list_jobs()}


def run_job(directory):
    import wallpaper_manager as manager
    request = json.loads((directory / 'request.json').read_text())
    status = json.loads((directory / 'status.json').read_text())
    results = []
    status.update(state='running', pid=os.getpid())
    previous_emit = manager.emit
    def update(event):
        if event['event'] == 'progress':
            status['current_title'] = event.get('title') or ''
        elif event['event'] == 'item':
            result = dict(event, batch=status['batch'], group=status['group'])
            results.append(result)
            status['completed'] += 1
            status['failed' if event['status'] == 'failed' else 'done'] += 1
            with (directory / 'events.jsonl').open('a') as log: log.write(json.dumps(result, ensure_ascii=False) + '\n')
        atomic(directory / 'status.json', status)
    manager.emit = update
    try:
        for index, batch in enumerate(request['batches']):
            status.update(batch=index + 1, group=batch['group'], label=batch.get('label') or '',
                          message=f'Importing batch {index + 1}/{len(request["batches"])}: {batch.get("label") or batch["group"] or "Ungrouped"}')
            atomic(directory / 'status.json', status)
            try:
                while True:
                    try:
                        manager.execute(dict(batch, action='import', confirmed=True))
                        break
                    except core.ImportFailure as error:
                        if 'Another wallpaper import is running.' not in str(error):
                            raise
                        status['message'] = 'Waiting for the current wallpaper operation to finish.'
                        atomic(directory / 'status.json', status)
                        time.sleep(0.5)
            except (ValueError, OSError, subprocess.SubprocessError, KeyError) as error:
                # A batch-level failure (for example a held import lock) is visible
                # per unfinished item; later batches remain independent.
                completed_sources = {r.get('source') for r in results}
                for item in batch['items']:
                    if item['source'] not in completed_sources:
                        update(dict(event='item', status='failed', source=item['source'], title=item['title'], details=str(error)))
        status.update(state='completed' if not status['failed'] else 'completed-with-errors',
                      message=f'{status["done"]}/{status["total"]} imported · {status["failed"]} failed. Open Details for results.', results=results)
    except BaseException as error:
        status.update(state='interrupted', message=str(error), results=results)
        raise
    finally:
        manager.emit = previous_emit
        atomic(directory / 'status.json', status)
    try:
        subprocess.run(['notify-send', '-a', 'Wallpaper Manager', 'Wallpaper import finished', status['message']],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
    except (OSError, subprocess.SubprocessError): pass


def worker(folder):
    folder = Path(folder)
    # Keep journals/work files beside the selected spool, including disposable
    # test projects. Production passes PROJECT/data/jobs.
    core.PROJECT = folder.parents[1]
    folder.mkdir(parents=True, exist_ok=True)
    try: os.nice(10)
    except OSError: pass
    with (folder / 'worker.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        for directory in sorted(folder.iterdir()):
            status = directory / 'status.json'
            if not status.is_file(): continue
            state = json.loads(status.read_text())
            if state['state'] == 'pending':
                try: run_job(directory)
                except BaseException: continue


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == '--worker': worker(sys.argv[2])
