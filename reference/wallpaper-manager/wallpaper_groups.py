"""Shared grouping metadata. Empty group means a standalone theme, never a catch-all."""
import json
import os
from pathlib import Path


def config_path():
    return Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config')) / 'omarchy/theme-groups.json'


def load():
    path = config_path()
    data = json.loads(path.read_text()) if path.is_file() else {'version': 1, 'assignments': {}, 'first': {}}
    if not isinstance(data.get('assignments'), dict) or not isinstance(data.get('first', {}), dict):
        raise ValueError('Invalid theme group metadata')
    return data


def clean(value):
    value = str(value).strip()
    if len(value) > 100 or any(ord(c) < 32 or c in '/\\' for c in value) or value in {'.', '..'}:
        raise ValueError('Use a group name of up to 100 characters without slashes or control characters.')
    return value


def group_for(slug, record=None, data=None):
    data = load() if data is None else data
    return data['assignments'].get(slug, (record or {}).get('group', ''))


def members(records, data=None):
    data = load() if data is None else data
    grouped = {}
    for slug, record in records.items():
        group = group_for(slug, record, data)
        grouped.setdefault(group, []).append(slug)
    for group, slugs in grouped.items():
        slugs.sort(key=lambda s: (s != data.get('first', {}).get(group), records[s].get('title', s).casefold(), s))
    return grouped


def prompt(default=''):
    groups = sorted(set(load()['assignments'].values()) - {''}, key=str.casefold)
    if groups:
        print('Existing groups: ' + ', '.join(groups))
    value = input(f'Anime / type group [Enter = {default or "ungrouped"}; - = ungrouped]: ').strip()
    return clean('' if value == '-' else value or default)
