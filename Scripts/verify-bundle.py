#!/usr/bin/env python3
"""Verify the complete signed iPhone + Watch development bundle before packaging."""
from pathlib import Path
import argparse, plistlib, subprocess, json
p = argparse.ArgumentParser()
p.add_argument('app', type=Path)
p.add_argument('--group', required=True)
p.add_argument('--iphone-udid')
p.add_argument('--watch-udid')
p.add_argument('--report', type=Path)
a = p.parse_args()
app = a.app.resolve()
bundles = {
    'iphone': (app, 'dev.courselist.app'),
    'iphone-widget': (app / 'PlugIns/CourseListWidgets.appex', 'dev.courselist.app.widgets'),
    'watch': (app / 'Watch/CourseListWatchApp.app', 'dev.courselist.app.watch'),
    'watch-widget': (app / 'Watch/CourseListWatchApp.app/PlugIns/CourseListWatchWidgets.appex', 'dev.courselist.app.watch.widgets'),
}
report = {}
for role, (path, identifier) in bundles.items():
    assert path.is_dir(), path
    info = plistlib.load((path / 'Info.plist').open('rb'))
    assert info['CFBundleIdentifier'] == identifier
    assert info['CFBundleShortVersionString'] == '0.4.0' and info['CFBundleVersion'] == '5'
    assert info['CourseListAppGroupIdentifier'] == a.group
    entitlements = plistlib.loads(subprocess.check_output(['codesign', '-d', '--entitlements', ':-', str(path)], stderr=subprocess.DEVNULL))
    profile = plistlib.loads(subprocess.check_output(['security', 'cms', '-D', '-i', str(path / 'embedded.mobileprovision')], stderr=subprocess.DEVNULL))
    assert entitlements['com.apple.security.application-groups'] == [a.group]
    assert profile['Entitlements']['com.apple.security.application-groups'] == [a.group]
    device = a.watch_udid if role.startswith('watch') else a.iphone_udid
    if device: assert device in profile['ProvisionedDevices'], (role, 'device missing from profile')
    if role in ['iphone', 'watch']:
        assert info['CFBundleIcons']['CFBundlePrimaryIcon']['CFBundleIconName'] == 'AppIcon'
        assert (path / 'Assets.car').is_file()
    if role == 'watch':
        assert info['WKApplication'] is True
        assert info['WKCompanionAppBundleIdentifier'] == bundles['iphone'][1]
    if role.endswith('widget'):
        assert info['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.widgetkit-extension'
    report[role] = dict(bundleID=identifier, version='0.4.0', build='5', group=a.group,
                        provisionedDevices=profile['ProvisionedDevices'], expires=profile['ExpirationDate'].isoformat())
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
if a.report: a.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print('BUNDLE: 4 signed products verified; Watch embedded; icons present; version=0.4.0 (5)')
