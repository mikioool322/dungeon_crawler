#!/usr/bin/env python3
"""Offline validation of OpenCode V2 agent/skill pack, no third-party libraries."""
from pathlib import Path
import re, sys
root = Path(__file__).resolve().parents[1]
errors=[]
for path in sorted((root/'.opencode/skills').glob('*/SKILL.md')):
    data=path.read_text(encoding='utf-8')
    if not data.startswith('---\n') or data.count('---\n') < 2: errors.append(f'{path}: missing YAML frontmatter'); continue
    header=data.split('---\n',2)[1]
    for field in ('name:', 'description:'):
        if field not in header: errors.append(f'{path}: missing {field}')
    name=re.search(r'^name: (.+)$',header,re.M)
    if not name or name.group(1) != path.parent.name: errors.append(f'{path}: skill name mismatch')
    if not re.fullmatch(r'[a-z0-9]+(?:-[a-z0-9]+)*',path.parent.name): errors.append(f'{path}: invalid skill ID')
for path in sorted((root/'.opencode/agents').glob('*.md')):
    data=path.read_text(encoding='utf-8')
    if not data.startswith('---\n') or 'description:' not in data.split('---\n',2)[1]: errors.append(f'{path}: frontmatter/description missing')
    if re.search(r'^permission:', data, re.M): errors.append(f'{path}: V1 permission field found')
    if 'mode: ' not in data: errors.append(f'{path}: missing mode')
if errors:
    print('FAIL\n'+'\n'.join(errors)); sys.exit(1)
print(f'PASS: {len(list((root/".opencode/skills").glob("*/SKILL.md")))} skills, {len(list((root/".opencode/agents").glob("*.md")))} agents — structural validation only')
