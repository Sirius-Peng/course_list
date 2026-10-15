#!/usr/bin/env python3
"""Generate an iPhone-only test project when no watchOS simulator runtime is installed."""
from pathlib import Path
import subprocess
import yaml
import os
root = Path(__file__).resolve().parents[1]
spec = yaml.safe_load((root / 'project.yml').read_text())
spec['name'] = os.environ.get('COURSELIST_PROJECT_NAME', 'CourseListiPhoneOnly')
if os.environ.get('COURSELIST_TEAM'):
    spec['settings']['base']['DEVELOPMENT_TEAM'] = os.environ['COURSELIST_TEAM']
if os.environ.get('COURSELIST_APP_GROUP'):
    spec['settings']['base']['COURSELIST_APP_GROUP'] = os.environ['COURSELIST_APP_GROUP']
spec['packages']['ScheduleCore']['path'] = '.'
if os.environ.get('COURSELIST_INCLUDE_WATCH') != '1':
    spec['targets'].pop('CourseListWatchApp')
    spec['targets'].pop('CourseListWatchWidgets')
    spec['targets']['CourseListApp']['dependencies'] = [d for d in spec['targets']['CourseListApp']['dependencies'] if d.get('target') != 'CourseListWatchApp']
    spec['schemes'].pop('CourseListWatchApp')
for target in spec['targets'].values():
    absolute_sources = []
    for source in target['sources']:
        source = {'path': source} if isinstance(source, str) else dict(source)
        source['path'] = str(root / source['path'])
        absolute_sources.append(source)
    target['sources'] = absolute_sources
    for kind in ['info', 'entitlements']:
        if kind in target:
            path = Path(target[kind]['path'])
            if os.environ.get('COURSELIST_TEAM'):
                path = path.with_name('Device-' + path.name)
            target[kind]['path'] = str(root / path)
    if 'entitlements' in target and os.environ.get('COURSELIST_APP_GROUP'):
        target['entitlements']['properties']['com.apple.security.application-groups'] = [os.environ['COURSELIST_APP_GROUP']]

work = root / '.implementation'
work.mkdir(exist_ok=True)
path = work / ('device-with-watch.yml' if os.environ.get('COURSELIST_INCLUDE_WATCH') == '1' else 'iphone-only.yml')
path.write_text(yaml.safe_dump(spec, allow_unicode=True, sort_keys=False))
subprocess.run(['xcodegen', 'generate', '--spec', str(path), '--project-root', str(root), '--project', str(root)], check=True)

subprocess.run(["python3", str(root / "Scripts/fix-capabilities.py"), str(root / (spec["name"] + ".xcodeproj"))], check=True)
