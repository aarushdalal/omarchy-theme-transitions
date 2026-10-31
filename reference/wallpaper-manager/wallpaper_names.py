"""Display names for themes; stable installation slugs keep media links intact."""
import json
import os
from pathlib import Path
import re
import sys


def names():
    path = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config')) / 'omarchy/theme-names.json'
    return json.loads(path.read_text()) if path.is_file() else {}


def display_name(slug, labels=None):
    return (names() if labels is None else labels).get(slug, slug.replace('-', ' ').title())


def normalized(value):
    return re.sub(r'[\s_—–-]+', '-', value.strip().casefold())


def resolve_name(value, labels=None):
    labels = names() if labels is None else labels
    if value in labels:
        return value
    matches = [slug for slug, title in labels.items() if normalized(title) == normalized(value)]
    if len(matches) > 1:
        raise ValueError('Ambiguous theme name: ' + value)
    return matches[0] if matches else value


if __name__ == '__main__':
    mode, value = sys.argv[1:]
    print(resolve_name(value) if mode == '--resolve' else display_name(value))
