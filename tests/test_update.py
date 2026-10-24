"""Updater tests use isolated files, fake GitHub responses and a fake installer."""
import contextlib
import hashlib
import importlib.util
import io
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('fnw_update', ROOT / 'tools/update.py')
update = importlib.util.module_from_spec(spec)
spec.loader.exec_module(update)
SHA = 'a' * 40


class UpdaterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.project = self.base / 'factorio'
        (self.project / 'mods').mkdir(parents=True)
        (self.project / 'compose.yaml').write_text('services: {}\n')
        self.archive = self.base / 'source.zip'
        with zipfile.ZipFile(self.archive, 'w') as z:
            for folder in ('mod', 'tools'):
                for file in (ROOT / folder).rglob('*'):
                    if file.is_file() and '__pycache__' not in file.parts:
                        z.write(file, 'source/' + file.relative_to(ROOT).as_posix())
            z.write(ROOT / 'LICENSE', 'source/LICENSE')
        self.downloads = 0
        self.installs = 0
        self.fail_install = False
        self.real_run = subprocess.run

    def fake_run(self, args, **kwargs):
        if args[0] == 'gh':
            endpoint = args[-1]
            if '/commits/' in endpoint:
                return subprocess.CompletedProcess(args, 0, json.dumps({'sha': SHA}).encode())
            self.assertEqual(endpoint, 'repos/leMalla/factory-night-watch/zipball/' + SHA)
            self.downloads += 1
            kwargs['stdout'].write(self.archive.read_bytes())
            return subprocess.CompletedProcess(args, 0)
        if args[0] == 'sudo':
            self.installs += 1
            if self.fail_install:
                raise subprocess.CalledProcessError(1, args)
            installer = Path(args[2])
            for file in installer.parent.glob('factory-night-watch_*.zip'):
                shutil.copy2(file, self.project / 'mods' / file.name)
            return subprocess.CompletedProcess(args, 0)
        return self.real_run(args, **kwargs)

    def invoke(self, *args):
        with patch.object(sys, 'argv', ['factorio-mod-update', '--project', str(self.project), *args]), \
             patch.object(update.os, 'geteuid', return_value=1000), \
             patch.object(update.shutil, 'which', return_value='/test/gh'), \
             patch.object(update.subprocess, 'run', side_effect=self.fake_run), \
             patch.dict(os.environ, {'XDG_STATE_HOME': str(self.base / 'state')}), \
             contextlib.redirect_stdout(io.StringIO()):
            update.main()

    def states(self):
        return list((self.base / 'state').rglob('*.json'))

    def test_check_does_not_download_or_install(self):
        self.invoke('--check')
        self.assertEqual((self.downloads, self.installs), (0, 0))
        self.assertEqual(self.states(), [])

    def test_build_only_contains_license_without_server_changes(self):
        output = self.base / 'output'
        self.invoke('--build-only', str(output))
        self.assertEqual((self.downloads, self.installs), (1, 0))
        archive = next(output.glob('factory-night-watch_*.zip'))
        with zipfile.ZipFile(archive) as z:
            license_path = next(n for n in z.namelist() if n.endswith('/LICENSE'))
            self.assertEqual(z.read(license_path), (ROOT / 'LICENSE').read_bytes())
        self.assertEqual(self.states(), [])

    def test_success_then_noop_and_force(self):
        self.invoke()
        self.assertEqual((self.downloads, self.installs), (1, 1))
        state = self.states()[0]
        self.assertEqual(stat.S_IMODE(state.stat().st_mode), 0o600)
        self.assertEqual(json.loads(state.read_text())['commit'], SHA)
        self.invoke()
        self.assertEqual((self.downloads, self.installs), (1, 1))
        self.invoke('--force')
        self.assertEqual((self.downloads, self.installs), (2, 2))

    def test_failed_install_does_not_record_success(self):
        self.fail_install = True
        with self.assertRaises(subprocess.CalledProcessError):
            self.invoke()
        self.assertEqual(self.states(), [])

    def test_modified_zip_is_reinstalled(self):
        self.invoke()
        next((self.project / 'mods').glob('*.zip')).write_bytes(b'manually changed')
        self.invoke()
        self.assertEqual(self.installs, 2)

    def test_unreadable_uid845_file_uses_recorded_fingerprint(self):
        self.invoke()
        target = next((self.project / 'mods').glob('*.zip'))
        installed = json.loads(self.states()[0].read_text())
        with patch.object(update, 'sha256', side_effect=PermissionError):
            self.assertTrue(update.matches_installation(target, installed))
            target.write_bytes(b'changed')
            self.assertFalse(update.matches_installation(target, installed))

    def test_bad_source_archive_never_invokes_installer(self):
        self.archive.write_bytes(b'not a zip')
        with self.assertRaises(zipfile.BadZipFile):
            self.invoke()
        self.assertEqual(self.installs, 0)

    def test_traversal_and_symlink_rejected(self):
        for name, mode in [('source/../../escape', 0), ('/absolute', 0),
                           ('source/link', stat.S_IFLNK | 0o777)]:
            with self.subTest(name=name):
                with zipfile.ZipFile(self.archive, 'w') as z:
                    entry = zipfile.ZipInfo(name)
                    entry.external_attr = mode << 16
                    z.writestr(entry, b'bad')
                with self.assertRaises(ValueError):
                    update.extract_source(self.archive, self.base / 'extract')
        self.assertFalse((self.base / 'escape').exists())


if __name__ == '__main__':
    unittest.main()
