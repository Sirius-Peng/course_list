#!/usr/bin/env python3
"""Keep nested target capability dictionaries as OpenStep plist dictionaries."""
from pathlib import Path
import re
import sys
root = Path(__file__).resolve().parents[1]
projects = [Path(p) for p in sys.argv[1:]] or [root/'CourseList.xcodeproj', root/'CourseListiPhoneOnly.xcodeproj']
for project in projects:
    path = project/'project.pbxproj'
    if not path.exists():
        continue
    text = path.read_text()
    fixed, count = re.subn(r'SystemCapabilities = "[^\n]*com\.apple\.ApplicationGroups\.iOS[^\n]*";',
        'SystemCapabilities = { com.apple.ApplicationGroups.iOS = { enabled = 1; }; };', text)
    if count:
        path.write_text(fixed)
        print(f'Fixed nested App Groups capabilities: {project.name} ({count} targets)')
