"""Shared stock-theme visibility rules for user-owned desktop launchers."""
import json
import os
from pathlib import Path


def hidden_defaults(stock, profile='omarchy'):
    config = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config')) / 'omarchy/wallpaper-library.json'
    registry = json.loads(config.read_text()) if config.is_file() else {}
    key = 'omarchy_stock_theme_allowlist' if profile == 'omarchy' else 'daemonos_stock_theme_allowlist'
    allowed = registry.get(key)
    if allowed is None:
        return set()
    if not isinstance(allowed, list) or any(not isinstance(slug, str) for slug in allowed):
        raise ValueError(f'Invalid {profile} default-theme allowlist')
    stock = Path(stock)
    roots = {stock, Path('/usr/share/omarchy/themes')}
    defaults = {p.name for root in roots if root.is_dir() for p in root.iterdir() if p.is_dir()}
    return defaults - set(allowed)
