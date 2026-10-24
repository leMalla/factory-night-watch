#!/usr/bin/env python3
"""Download, build and install Factory Night Watch directly from GitHub."""
import argparse
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path, PurePosixPath
from urllib.parse import quote

REPOSITORY = 'leMalla/factory-night-watch'
MOD_NAME = 'factory-night-watch'


def run(args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def api(endpoint):
    return run(['gh', 'api', '--hostname', 'github.com', endpoint],
               stdout=subprocess.PIPE).stdout


def extract_source(archive, destination):
    """Extract a single-root source archive; reject unsafe and oversized entries."""
    with zipfile.ZipFile(archive) as z:
        entries = z.infolist()
        if len(entries) > 2500 or sum(e.file_size for e in entries) > 64 * 1024 * 1024:
            raise ValueError('Unerwartet grosses Quellarchiv.')
        roots = set()
        for entry in entries:
            name = entry.filename
            parts = PurePosixPath(name).parts
            mode = entry.external_attr >> 16
            if not parts or name.startswith('/') or '\\' in name or '..' in parts or stat.S_ISLNK(mode):
                raise ValueError('Unsicherer Pfad im Quellarchiv.')
            roots.add(parts[0])
        if len(roots) != 1:
            raise ValueError('Unerwartete Archivstruktur.')
        if z.testzip() is not None:
            raise ValueError('Archivpruefung fehlgeschlagen.')
        z.extractall(destination)
    source = destination / roots.pop()
    if not (source / 'tools/build.py').is_file() or not (source / 'mod/info.json').is_file():
        raise ValueError('Factory-Night-Watch-Quellen fehlen.')
    return source


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fingerprint(path):
    s = path.stat()
    return [s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns]


def matches_installation(target, installed):
    if not target.is_file():
        return False
    try:
        return sha256(target) == installed.get('zip_sha256')
    except PermissionError:
        # UID 845 owns Docker mod files; a normal SSH user may only be able to stat them.
        return fingerprint(target) == installed.get('target_fingerprint')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', type=Path, default=Path.home() / 'docker/factorio',
                        help='Factorio data directory (default: ~/docker/factorio)')
    parser.add_argument('--ref', default='main', help='Branch, tag or commit (default: main)')
    parser.add_argument('--check', action='store_true', help='Check for an update without installing')
    parser.add_argument('--build-only', type=Path, metavar='DIRECTORY',
                        help='Download/build files into a directory without stopping the server')
    parser.add_argument('--force', action='store_true', help='Install even if this exact commit is recorded')
    args = parser.parse_args()
    if hasattr(os, 'geteuid') and os.geteuid() == 0:
        raise SystemExit('Ohne sudo starten; nur die eigentliche Installation fordert sudo an.')
    if not shutil.which('gh'):
        raise SystemExit('GitHub CLI fehlt. Zuerst gh installieren und gh auth login ausfuehren.')
    project = args.project.expanduser().resolve()
    if not args.check and not args.build_only and not (project / 'compose.yaml').is_file():
        raise SystemExit('compose.yaml fehlt. --project auf den Factorio-Datenordner setzen.')
    state_root = Path(os.environ.get('XDG_STATE_HOME', str(Path.home() / '.local/state')))
    state_path = state_root / MOD_NAME / (hashlib.sha256(str(project).encode()).hexdigest()[:16] + '.json')
    try:
        installed = json.loads(state_path.read_text())
    except (OSError, ValueError):
        installed = {}
    # Resolve the branch once, then download that immutable commit.
    metadata = json.loads(api(f'repos/{REPOSITORY}/commits/{quote(args.ref, safe="")}'))
    commit = metadata['sha']
    if not re.fullmatch(r'[a-f0-9]{40}', commit):
        raise ValueError('Unerwartete Commit-ID.')
    target = project / 'mods' / f'{MOD_NAME}_{installed.get("version", "unknown")}.zip'
    current = installed.get('commit') == commit and matches_installation(target, installed)
    if args.check:
        print(('Bereits installiert: ' if current else 'Installation verfuegbar: ') + commit[:12])
        return
    if current and not args.force and not args.build_only:
        print('Bereits aktuell; kein Serverneustart erforderlich.')
        return
    with tempfile.TemporaryDirectory(prefix='factory-night-watch-') as temporary:
        temp = Path(temporary)
        archive = temp / 'source.zip'
        print('Lade GitHub-Stand ' + commit[:12] + ' ...', flush=True)
        with archive.open('wb') as stream:
            run(['gh', 'api', '--hostname', 'github.com', f'repos/{REPOSITORY}/zipball/{commit}'], stdout=stream)
        source = extract_source(archive, temp / 'source')
        info = json.loads((source / 'mod/info.json').read_text())
        version = info['version']
        if info['name'] != MOD_NAME or not re.fullmatch(r'\d+\.\d+\.\d+', version):
            raise ValueError('Unerwartete Mod-Metadaten.')
        run([sys.executable, str(source / 'tools/build.py')], cwd=source)
        dist = source / 'dist'
        mod_zip = dist / f'{MOD_NAME}_{version}.zip'
        installer = dist / 'install-factory-night-watch.sh'
        if args.build_only:
            output = args.build_only.expanduser().resolve()
            output.mkdir(parents=True, exist_ok=True)
            shutil.copy2(mod_zip, output / mod_zip.name)
            shutil.copy2(installer, output / installer.name)
            print('Dateien erstellt: ' + str(output))
            return
        print('Installiere ' + version + ' mit Ruecksetzpunkt ...', flush=True)
        run(['sudo', 'bash', str(installer), str(project)])
        # Only record success after the installer confirms InGame.
        state_path.parent.mkdir(parents=True, exist_ok=True)
        state_path.parent.chmod(0o700)
        record = {'repository': REPOSITORY, 'commit': commit, 'version': version,
                  'zip_sha256': sha256(mod_zip), 'project': str(project),
                  'target_fingerprint': fingerprint(project / 'mods' / mod_zip.name)}
        staged = state_path.with_suffix('.tmp')
        staged.write_text(json.dumps(record, indent=2) + '\n')
        staged.chmod(0o600)
        staged.replace(state_path)
        # Refresh the installed command, never overwrite a developer's source file.
        command = Path(__file__).resolve()
        if command.name == 'factorio-mod-update':
            replacement = command.with_name(command.name + '.tmp')
            replacement.write_bytes((source / 'tools/update.py').read_bytes())
            replacement.chmod(0o700)
            replacement.replace(command)
        print('Installiert: ' + version + ' (' + commit[:12] + ').')
        print('Clients brauchen dieselbe Mod-Version. Anleitung: docs/README.de.md')


if __name__ == '__main__':
    try:
        main()
    except (subprocess.CalledProcessError, OSError, ValueError, KeyError, zipfile.BadZipFile) as exc:
        raise SystemExit('Update abgebrochen: ' + str(exc)) from None
