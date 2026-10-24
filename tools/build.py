"""Build the Factorio mod ZIP and embedded Docker installer, without third-party packages."""
import ast
import base64
import configparser
import hashlib
import json
import re
import shutil
import subprocess
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'mod'
info = json.loads((SOURCE / 'info.json').read_text())
name, version = info['name'], info['version']
assert re.fullmatch(r'[a-z0-9-]+', name)
assert re.fullmatch(r'\d+\.\d+\.\d+', version)
catalogs = []
for lang in ('de', 'en'):
    config = configparser.ConfigParser(interpolation=None, strict=True)
    config.read(SOURCE / 'locale' / lang / 'guard.cfg', encoding='utf-8')
    catalogs.append({(section, key) for section in config.sections() for key in config[section]})
assert catalogs[0] == catalogs[1], 'Locale keys differ'
output = ROOT / 'dist'
output.mkdir(exist_ok=True)
archive = output / f'{name}_{version}.zip'
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as z:
    for file in sorted(SOURCE.rglob('*')):
        if file.is_file():
            assert file.suffix in ('.lua', '.json', '.cfg', '.txt'), f'Unexpected mod file: {file}'
            entry = zipfile.ZipInfo(f'{name}_{version}/' + file.relative_to(SOURCE).as_posix(), (2026, 10, 24, 12, 0, 0))
            entry.compress_type = zipfile.ZIP_DEFLATED
            entry.external_attr = 0o644 << 16
            z.writestr(entry, file.read_bytes())
    entry = zipfile.ZipInfo(f'{name}_{version}/LICENSE', (2026, 10, 24, 12, 0, 0))
    entry.compress_type = zipfile.ZIP_DEFLATED
    entry.external_attr = 0o644 << 16
    z.writestr(entry, (ROOT / 'LICENSE').read_bytes())
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    assert not any(b'fnw-it-rule' in z.read(n) for n in z.namelist()), 'Test bridge leaked into release'
payload = archive.read_bytes()
encoded = base64.b64encode(payload).decode()
wrapped = '\n'.join(encoded[i:i+100] for i in range(0, len(encoded), 100))
template = (ROOT / 'tools' / 'installer-template.sh').read_text()
template = re.sub(r'VERSION = "[^"]+"', f'VERSION = "{version}"', template)
template = template.replace('Factory Night Watch 0.3.0 mit', f'Factory Night Watch {version} mit')
script = template.replace('__MOD_BASE64__', wrapped).replace('__MOD_SHA256__', hashlib.sha256(payload).hexdigest())
installer = output / 'install-factory-night-watch.sh'
installer.write_text(script, encoding='utf-8', newline='\n')
python = script.split("<<'PY'\n", 1)[1].rsplit('\nPY', 1)[0]
ast.parse(python)
assert base64.b64decode(re.search(r'PAYLOAD = """(.*?)"""', python, re.S)[1]) == payload
if shutil.which('bash'):
    subprocess.run(['bash', '-n', str(installer)], check=True)
print(f'Built {archive.name} and {installer.name}; validation passed.')
