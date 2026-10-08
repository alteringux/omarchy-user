#!/usr/bin/env bash
# Checkout's credential cleanup needs a URL for every tracked gitlink.
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$HERE/.."
python3 - <<'PY'
import configparser
import subprocess

config = configparser.ConfigParser(interpolation=None)
config.read('.gitmodules')
urls = {entry['path']: entry.get('url', '').strip()
        for entry in config.values() if 'path' in entry}
entries = subprocess.check_output(['git', 'ls-files', '--stage', '-z']).split(b'\0')
paths = [entry.split(b'\t', 1)[1].decode() for entry in entries
         if entry.startswith(b'160000 ')]
for path in paths:
    assert urls.get(path), f'Missing submodule URL for {path}'
print(f'ok - {len(paths)} tracked submodule(s) have URLs')
PY
