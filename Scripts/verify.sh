#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .implementation/logs
swift test > .implementation/logs/swift-test.log 2>&1
grep 'Executed 59 tests, with 0 failures' .implementation/logs/swift-test.log >/dev/null
python3 - <<'PY'
from pathlib import Path
import yaml
p = yaml.safe_load(Path('project.yml').read_text())
assert str(p['options']['deploymentTarget']['iOS']) == '26.0'
for name in ['CourseListApp','CourseListWidgets','CourseListWatchApp','CourseListWatchWidgets']:
    assert name in p['targets']
    assert p['targets'][name]['entitlements']['properties']['com.apple.security.application-groups'] == ['group.dev.courselist.shared']
s = Path('Widgets/CourseStatusWidget.swift').read_text()
assert '.supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])' in s
print('MODIFIED: 59 tests passed; iOS=26.0; lock-screen families=3')
PY
