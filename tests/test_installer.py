"""Exercise the embedded installer with real temporary files and fake Docker only."""
import base64
import builtins
import contextlib
import gzip
import hashlib
import io
import itertools
import json
import os
import re
import stat
import subprocess
import sys
import tarfile
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='fnw-installer-test-')
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.project = self.base / 'factorio'
        for name in ('mods', 'config', 'saves'):
            (self.project / name).mkdir(parents=True)
        (self.project / 'compose.yaml').write_text('services: {}\n')
        (self.project / 'saves/world.zip').write_bytes(b'original world')
        self.settings = self.project / 'config/server-settings.json'
        self.settings.write_text(json.dumps({'auto_pause': True, 'name': 'Test server'}))
        self.settings.chmod(0o604)
        self.mod_list = self.project / 'mods/mod-list.json'
        self.mod_list.write_text(json.dumps({'mods': [{'name': 'base', 'enabled': True}]}))
        self.mod_list.chmod(0o644)
        self.info = json.loads((ROOT / 'mod/info.json').read_text())
        self.version = self.info['version']
        self.target = self.project / 'mods' / ('factory-night-watch_' + self.version + '.zip')
        self.target.write_bytes(b'previous target bytes')
        self.target.chmod(0o644)
        self.obsolete = self.project / 'mods/factory-night-watch_0.0.1.zip'
        self.obsolete.write_bytes(b'previous older version')
        self.obsolete.chmod(0o600)
        self.originals = {p: (p.read_bytes(), stat.S_IMODE(p.stat().st_mode))
                          for p in (self.settings, self.mod_list, self.target, self.obsolete)}
        payload = io.BytesIO()
        with zipfile.ZipFile(payload, 'w') as z:
            z.writestr('factory-night-watch_' + self.version + '/info.json', json.dumps(self.info))
        self.payload = payload.getvalue()
        template = (ROOT / 'tools/installer-template.sh').read_text()
        script = template.split("<<'PY'\n", 1)[1].rsplit('\nPY', 1)[0]
        script = re.sub(r'VERSION = "[^"]+"', 'VERSION = "' + self.version + '"', script)
        script = script.replace('__MOD_BASE64__', base64.b64encode(self.payload).decode())
        self.script = script.replace('__MOD_SHA256__', hashlib.sha256(self.payload).hexdigest())
        self.commands = []
        self.stopped = False
        self.start_count = 0
        self.start_failure = False
        self.readiness_timeout = False
        self.exit_code = 0
        self.gzip_failure = False
        self.stop_failure = False
        self.backup_read_failure = False
        self.snapshot_read_failure = False
        self.compose_project = 'factorio-test'
        self.label_project = 'factorio-test'
        self.service = 'game'
        self.label_service = 'game'
        self.ownership_calls = []

    def check_output(self, args, **kwargs):
        self.commands.append(list(args))
        if args[0:2] == ['docker', 'compose'] and args[-3:] == ['config', '--format', 'json']:
            return json.dumps({'name': self.compose_project,
                               'services': {self.service: {'container_name': 'factorio'},
                                            'database': {'image': 'untouched'}}})
        if args[0:3] == ['docker', 'inspect', '--format']:
            self.assertEqual(args[-1], 'factorio')
            if args[3] == '{{json .Config.Labels}}':
                return json.dumps({'com.docker.compose.service': self.label_service,
                                   'com.docker.compose.project': self.label_project})
            if args[3] == '{{json .Mounts}}':
                return json.dumps([{'Destination': '/factorio', 'Source': str(self.project)}])
            if args[3] == '{{.State.ExitCode}}':
                return str(self.exit_code) + '\n'
        raise AssertionError('Unexpected subprocess.check_output: ' + repr(args))

    def fake_run(self, args, **kwargs):
        self.commands.append(list(args))
        if args[0:2] == ['docker', 'compose']:
            action = args[4:]
            if action[0] == 'stop':
                self.assertEqual(action, ['stop', '-t', '120', self.service])
                self.stopped = True
                if self.stop_failure:
                    self.stop_failure = False
                    raise subprocess.CalledProcessError(1, args)
            elif action[0] == 'up':
                self.assertEqual(action, ['up', '-d', '--no-deps', self.service])
                self.start_count += 1
                if self.start_failure and self.start_count == 1:
                    raise subprocess.CalledProcessError(1, args)
                self.stopped = False
            else:
                raise AssertionError('Unexpected Compose mutation: ' + repr(args))
            return subprocess.CompletedProcess(args, 0)
        if args[0] == 'gzip':
            if self.gzip_failure:
                raise subprocess.CalledProcessError(1, args)
            with gzip.open(args[-1], 'rb') as stream:
                stream.read()
            return subprocess.CompletedProcess(args, 0)
        if args[0:2] == ['docker', 'logs']:
            return subprocess.CompletedProcess(args, 0, stdout=('Starting without InGame\n' if self.readiness_timeout else 'Ready to(InGame)\n'), stderr='')
        raise AssertionError('Unexpected subprocess.run: ' + repr(args))

    def execute(self):
        original_open = builtins.open
        original_read = Path.read_bytes
        original_add = tarfile.TarFile.add

        def guarded_open(file, *args, **kwargs):
            if str(file) == '/run/lock/factorio-backup.lock':
                file = self.base / 'backup.lock'
            return original_open(file, *args, **kwargs)

        def guarded_read(path):
            if self.snapshot_read_failure and path == self.target:
                raise OSError('injected original-file read failure')
            return original_read(path)

        def guarded_add(archive, name, *args, **kwargs):
            if self.backup_read_failure and self.stopped and Path(name) == self.project / 'mods':
                raise OSError('injected post-stop backup read failure')
            return original_add(archive, name, *args, **kwargs)

        clock = itertools.count(0, 31)
        namespace = {'__name__': '__installer_test__'}
        with patch.object(sys, 'argv', ['installer', str(self.project)]), \
             patch.object(builtins, 'open', side_effect=guarded_open), \
             patch.object(Path, 'read_bytes', guarded_read), \
             patch.object(tarfile.TarFile, 'add', guarded_add), \
             patch.object(subprocess, 'check_output', side_effect=self.check_output), \
             patch.object(subprocess, 'run', side_effect=self.fake_run), \
             patch.object(os, 'umask', return_value=0o022), \
             patch.object(os, 'chown', side_effect=lambda *args: self.ownership_calls.append(args)), \
             patch.object(os, 'lchown', side_effect=lambda *args: self.ownership_calls.append(args)), \
             patch('time.monotonic', side_effect=lambda: next(clock)), \
             patch('time.sleep'), \
             contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            try:
                exec(compile(self.script, '<embedded-factorio-installer>', 'exec'), namespace)
            finally:
                lock = namespace.get('lock')
                if lock:
                    lock.close()

    def assert_originals(self):
        for path, (content, mode) in self.originals.items():
            self.assertEqual(path.read_bytes(), content, str(path))
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), mode, str(path))

    def mutations(self):
        return [args for args in self.commands if args[:2] == ['docker', 'compose']
                and args[4] in ('stop', 'up')]

    def test_success_targets_only_actual_factorio_service(self):
        self.execute()
        self.assertFalse(self.stopped)
        self.assertEqual(self.target.read_bytes(), self.payload)
        self.assertFalse(self.obsolete.exists())
        self.assertFalse(json.loads(self.settings.read_text())['auto_pause'])
        self.assertEqual(len(self.mutations()), 2)
        for args in self.mutations():
            self.assertEqual(args[-1], 'game')
            self.assertNotIn('database', args)
        self.assertTrue(any(call[1:] == (845, 845) for call in self.ownership_calls))
        backups = list((self.project / 'backups/night-watch-install').glob('*.tar.gz'))
        self.assertEqual(len(backups), 1)
        with tarfile.open(backups[0]) as archive:
            self.assertEqual(archive.extractfile('saves/world.zip').read(), b'original world')
            self.assertEqual(archive.extractfile('mods/' + self.obsolete.name).read(), b'previous older version')

    def test_post_stop_backup_read_failure_restarts_without_mutating_files(self):
        self.backup_read_failure = True
        with self.assertRaisesRegex(OSError, 'post-stop backup read'):
            self.execute()
        self.assertFalse(self.stopped)
        self.assertEqual(self.start_count, 1)
        self.assert_originals()
        self.assertEqual(list((self.project / 'backups/night-watch-install').glob('*.partial')), [])

    def test_start_failure_rolls_back_bytes_modes_and_restarts(self):
        self.start_failure = True
        with self.assertRaises(subprocess.CalledProcessError):
            self.execute()
        self.assertFalse(self.stopped)
        self.assertEqual(self.start_count, 2)
        self.assert_originals()
        self.assertEqual(list(self.project.rglob('*.guard-tmp')), [])

    def test_rollback_removes_new_target_if_it_did_not_exist(self):
        self.target.unlink()
        self.start_failure = True
        with self.assertRaises(subprocess.CalledProcessError):
            self.execute()
        self.assertFalse(self.target.exists())
        self.assertTrue(self.obsolete.exists())
        self.assertFalse(self.stopped)

    def test_original_file_read_failure_happens_before_stop(self):
        self.snapshot_read_failure = True
        with self.assertRaisesRegex(OSError, 'original-file read'):
            self.execute()
        self.assertEqual(self.mutations(), [])
        self.assertEqual(self.start_count, 0)

    def test_partial_stop_failure_still_attempts_restart(self):
        self.stop_failure = True
        with self.assertRaises(subprocess.CalledProcessError):
            self.execute()
        self.assertEqual(self.start_count, 1)
        self.assertFalse(self.stopped)
        self.assert_originals()

    def test_rollback_restores_original_configuration_symlink(self):
        shared = self.settings.with_name('shared-settings.json')
        self.settings.rename(shared)
        self.settings.symlink_to(shared.name)
        self.start_failure = True
        with self.assertRaises(subprocess.CalledProcessError):
            self.execute()
        self.assertTrue(self.settings.is_symlink())
        self.assertEqual(os.readlink(self.settings), shared.name)
        self.assert_originals()
        self.assertFalse(self.stopped)

    def test_readiness_timeout_restores_previous_installation(self):
        self.readiness_timeout = True
        with self.assertRaisesRegex(RuntimeError, '90 Sekunden'):
            self.execute()
        self.assertFalse(self.stopped)
        self.assertEqual(self.start_count, 2)
        self.assert_originals()

    def test_killed_server_exit_aborts_before_modification(self):
        self.exit_code = 137
        with self.assertRaisesRegex(RuntimeError, 'Exit 137'):
            self.execute()
        self.assertFalse(self.stopped)
        self.assertEqual(self.start_count, 1)
        self.assert_originals()

    def test_failed_archive_validation_restarts_original_service(self):
        self.gzip_failure = True
        with self.assertRaises(subprocess.CalledProcessError):
            self.execute()
        self.assertFalse(self.stopped)
        self.assert_originals()
        self.assertEqual(list((self.project / 'backups/night-watch-install').iterdir()), [])

    def test_unpacked_matching_mod_is_rejected_before_stop(self):
        folder = self.project / 'mods/arbitrary-checkout-name'
        folder.mkdir()
        (folder / 'info.json').write_text(json.dumps({'name': 'factory-night-watch', 'version': '9.9.9'}))
        with self.assertRaisesRegex(SystemExit, 'Entpackte'):
            self.execute()
        self.assertEqual(self.mutations(), [])
        self.assert_originals()
        self.assertTrue(folder.is_dir())

    def test_different_compose_project_is_rejected_before_stop(self):
        self.label_project = 'another-project'
        with self.assertRaisesRegex(SystemExit, 'anderen Compose-Projekt'):
            self.execute()
        self.assertEqual(self.mutations(), [])

    def test_unknown_compose_service_is_rejected_before_stop(self):
        self.label_service = 'unrelated'
        with self.assertRaisesRegex(SystemExit, 'Compose-Service'):
            self.execute()
        self.assertEqual(self.mutations(), [])

    def test_invalid_settings_json_is_rejected_before_stop(self):
        self.settings.write_text('invalid JSON')
        with self.assertRaises(ValueError):
            self.execute()
        self.assertEqual(self.mutations(), [])


if __name__ == '__main__':
    unittest.main()
