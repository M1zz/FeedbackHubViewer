# -*- coding: utf-8 -*-
"""스펙 한 벌을 그 앱의 Swift 와 대조해 결과를 찍는다. 어긋나면 1 로 끝낸다."""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import spec_drift  # noqa: E402

repo, rel, name = sys.argv[1], sys.argv[2], sys.argv[3]
spec = json.load(open(os.path.join(repo, rel), encoding='utf-8'))
written = spec_drift.written_metric_keys(repo)
mentioned = spec_drift.mentioned_strings(repo)

problems = []

for key in sorted(spec_drift.referenced_metrics(spec) - written):
    problems.append(f'지표 "{key}" 를 읽는데 앱 코드에 없습니다 (그 칸은 조용히 0 이 됩니다)')

for event in sorted(spec_drift.referenced_events(spec) - mentioned):
    problems.append(f'이벤트 "{event}" 를 읽는데 앱 코드에 없습니다 (퍼널 칸이 "보내지 않음"으로 남습니다)')

problems += spec_drift.internal_problems(spec)

if problems:
    print(f'✗   {name}')
    for line in problems:
        print(f'      {line}')
    sys.exit(1)

metrics = len(spec_drift.referenced_metrics(spec))
events = len(spec_drift.referenced_events(spec))
print(f'✓   {name}  (지표 {metrics}개 · 이벤트 {events}개 대조)')
