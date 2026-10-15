#!/usr/bin/env python3
from pathlib import Path
import hashlib
import sys
root = Path(sys.argv[1]).resolve()
plan = root / 'IMPLEMENTATION_PLAN.md'
expected = (root / 'SHA256.txt').read_text().split()[0] if (root / 'SHA256.txt').exists() else (root / '.implementation/baseline/SHA256.txt').read_text().split()[0]
assert hashlib.sha256(plan.read_bytes()).hexdigest() == expected, 'Plan hash mismatch'
swift = list(root.glob('Sources/**/*.swift')) + list(root.glob('Apps/**/*.swift')) + list(root.glob('Shared/**/*.swift')) + list(root.glob('Widgets/**/*.swift'))
assert not swift and not list(root.glob('*.xcodeproj')), 'Source project remains'
print('BASELINE: plan hash verified; Swift=0; Xcode=0')
