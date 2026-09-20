# -*- coding: utf-8 -*-
"""스펙이 가리키는 것과 앱이 실제로 보내는 것을 대조한다.

**왜 있는가.** `sync-stats-specs.sh --check` 는 사본이 낡았는지만 본다. 그런데
두번알림에서 실제로 난 사고는 두 파일이 **똑같이 틀린** 경우였다. 앱이 알림 한도를
없애면서 `trial.prealerts` 를 더 이상 안 보내게 됐는데 스펙은 그 키로 "막힌 사람"을
세고 있었고, 없는 키는 0 으로 읽히니 그 칸은 그날부터 늘 0 이었다. 0 은 "없다"처럼
보이므로 화면도 사람도 몇 달 동안 아무 불평을 안 했다.

**못 잡는 것도 분명히 해 둔다. 이건 화재경보기이지 방화벽이 아니다:**

  · **얼어붙은 키** — 키는 아직 보내지만 값이 안 느는 경우(`alertLimitHits`).
    존재 여부만 보므로 통과한다.
  · **뜻이 바뀐 것** — `alertsMax` 는 멀쩡히 살아 있지만, 알림이 무료가 된 뒤로
    "결제에 가까운 정도"로 읽던 해석이 틀리게 됐다. 그건 사람이 아는 수밖에 없다.
  · 이벤트의 **슬라이스**(`paywall_shown:presentationMode` 의 뒷부분). 문자열을
    코드에서 이어 붙여 만들기 때문에(`"paywall_shown:" + feature.rawValue`)
    통째로는 어디에도 없다. 그래서 앞부분만 본다.
"""

import json
import os
import re

SWIFT_SKIP = ("/build/", "/.build/", "/DerivedData/", "/Pods/", "/.git/")
TEST_HINTS = ("Tests/", "Test/", "UITest", "Mock")


def _strip_comments(src: str) -> str:
    """주석을 지운다.

    ⚠️ 이게 없으면 이 검사는 **잡으려는 바로 그 버그를 놓친다.** 두번알림의
       리포터에는 "옛 키(`trial.prealerts`)는 늘지 않게 됐다" 는 주석이 있어서,
       주석을 세면 죽은 키가 살아 있는 것으로 보인다.
    """
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c == '"':                                   # 문자열 — 안의 // 는 주석이 아니다
            out.append(c); i += 1
            while i < n:
                if src[i] == '\\':
                    out.append(src[i:i + 2]); i += 2; continue
                out.append(src[i])
                if src[i] == '"':
                    i += 1; break
                i += 1
            continue
        if c == '/' and i + 1 < n and src[i + 1] == '/':
            while i < n and src[i] != '\n':
                i += 1
            continue
        if c == '/' and i + 1 < n and src[i + 1] == '*':
            depth, i = 1, i + 2                        # Swift 의 블록 주석은 중첩된다
            while i < n and depth:
                if src.startswith('/*', i):
                    depth += 1; i += 2
                elif src.startswith('*/', i):
                    depth -= 1; i += 2
                else:
                    i += 1
            continue
        out.append(c); i += 1
    return ''.join(out)


def _swift_sources(repo: str):
    """앱의 Swift 원문 (주석 제거, 테스트·빌드 산출물 제외)."""
    for root, dirs, files in os.walk(repo):
        dirs[:] = [d for d in dirs if not d.startswith('.') and d not in ('build', 'Pods')]
        for name in files:
            if not name.endswith('.swift'):
                continue
            path = os.path.join(root, name)
            rel = path[len(repo):]
            if any(s in rel for s in SWIFT_SKIP) or any(h in rel for h in TEST_HINTS):
                continue
            try:
                yield rel, _strip_comments(open(path, encoding='utf-8', errors='replace').read())
            except OSError:
                continue


def written_metric_keys(repo: str) -> set:
    """앱이 스냅샷에 **써 넣는** 지표 키.

    ⚠️ "코드에 그 글자가 있는가" 로는 안 된다. 앱은 자기 통계 화면에서 **옛 스냅샷을
       읽으려고** 죽은 키를 그대로 들고 있다 — 두번알림의 `UsageInsights` 가
       `metrics["trial.prealerts"]` 를 지금도 읽는다. 읽는 자리까지 세면 이 검사는
       잡으려던 바로 그 버그를 놓친다(실제로 처음엔 놓쳤다).

    그래서 **쓰는 모양** 셋만 본다:
      · `metrics["키"] = …`  (대입. `==` 비교나 `let x = metrics["키"]` 는 안 걸린다)
      · `"키": <숫자식>`      (딕셔너리 리터럴. 값이 따옴표로 시작하면 제외 —
                              삼항 연산자 `cond ? "a" : "b"` 가 키로 잡히던 자리다)
      · `case 키`             (enum rawValue 를 키로 쓰는 앱. 그 파일이 실제로
                              `rawValue] =` 로 쓰고 있을 때만 센다)
    """
    keys = set()
    for _, src in _swift_sources(repo):
        # 지표를 만드는 파일만 본다. 아무 딕셔너리 리터럴이나 세면 엉뚱한 낱말이
        # "보내는 키" 로 들어오고, 그러면 죽은 키가 살아 있는 것으로 보인다.
        if 'metrics' not in src:
            continue
        keys.update(re.findall(r'\[\s*"([^"\n]+)"\s*\]\s*=(?!=)', src))
        # ⚠️ `switch` 의 `case "키":` 를 먼저 지운다. 그게 딕셔너리 항목과 모양이 같아서,
        #    **라벨을 붙여 주는 switch 문 하나 때문에 죽은 키가 살아 있는 것으로 보였다**
        #    (두번알림 `UsageStatsView` 의 `case "trial.prealerts": return "…"`).
        without_case = re.sub(r'\bcase\s+(?:"[^"\n]*"\s*,?\s*)+', ' ', src)
        keys.update(re.findall(r'"([^"\n]+)"\s*:\s*(?!")', without_case))
        if re.search(r'rawValue\s*\]\s*=(?!=)', src):
            keys.update(re.findall(r'\bcase\s+([A-Za-z_]\w*)', src))
    keys.discard('')
    return keys


def mentioned_strings(repo: str) -> set:
    """앱 코드에 나오는 문자열 낱말 전부 — **이벤트 이름 확인용.**

    이벤트는 쓰는 모양이 제각각이라(`log("timer_start")`, `case x = "paywall_view"`,
    `return "premium_feature_used:\\(feature.rawValue)"`) 지표처럼 좁힐 수가 없다.
    그래서 이 쪽은 느슨하다 — **없는 것은 잡지만, 있다고 해서 지금도 나간다는 보장은
    없다.** 퍼널 칸이 비는 것은 화면이 "보내지 않음" 으로 이미 드러내 주므로
    지표만큼 위험하지 않다.
    """
    tokens = set()
    for _, src in _swift_sources(repo):
        for literal in re.findall(r'"([^"\n]*?)(?:\\\(|")', src):
            tokens.add(literal)
            # 보간으로 만드는 이름은 앞부분만 코드에 있다:
            #   "paywall_converted:\\(trigger.rawValue)"
            tokens.add(literal.rstrip(':').rstrip('.'))
            tokens.add(literal.split(':', 1)[0])
        tokens.update(re.findall(r'\bcase\s+([A-Za-z_]\w*)', src))
    tokens.discard('')
    return tokens


# ── 스펙이 무엇을 가리키는가 ────────────────────────────────────────────────

def _conditions(node):
    """중첩된 어디에 있든 Condition 모양(metric/sum/ratio/derived)을 전부 찾아낸다."""
    if isinstance(node, dict):
        if any(k in node for k in ('metric', 'sum', 'ratio', 'derived')):
            yield node
        for v in node.values():
            yield from _conditions(v)
    elif isinstance(node, list):
        for v in node:
            yield from _conditions(v)


def referenced_metrics(spec: dict) -> set:
    """카드·규칙·플래그가 읽는 지표 키. `derived` 이름은 지표가 아니므로 뺀다."""
    derived_names = {d['name'] for d in spec.get('derived', []) if 'name' in d}
    keys = set()
    for cond in _conditions(spec):
        if cond.get('derived'):
            continue                                   # 지표가 아니라 파생값 이름이다
        if cond.get('metric'):
            keys.add(cond['metric'])
        keys.update(cond.get('sum') or [])
        keys.update(cond.get('ratio') or [])
    # 타일의 condition, derived 의 from/subtract 는 Condition 모양이 아니다.
    for tile in _find(spec, 'tiles'):
        if tile.get('condition'):
            keys.add(tile['condition'])
    for d in spec.get('derived', []):
        for slot in ('flag', 'from', 'subtract'):
            if d.get(slot):
                keys.add(d[slot])
    for flag in ('accessFlag', 'paidFlag', 'trialFlag', 'compedFlag', 'addOnFlag', 'legacyPaidFlag'):
        if spec.get(flag):
            keys.add(spec[flag])
    return {k for k in keys if k not in derived_names}


def _find(node, key):
    """중첩 어디에 있든 `key` 라는 이름의 리스트를 펼쳐 준다."""
    if isinstance(node, dict):
        if isinstance(node.get(key), list):
            for item in node[key]:
                if isinstance(item, dict):
                    yield item
        for v in node.values():
            yield from _find(v, key)
    elif isinstance(node, list):
        for v in node:
            yield from _find(v, key)


def referenced_events(spec: dict) -> set:
    """퍼널 단계와 모먼트가 읽는 이벤트 **기본형**(슬라이스 앞부분)."""
    names = set()
    for step in _find(spec, 'steps'):
        if step.get('event'):
            names.add(step['event'])
        names.update(step.get('anyOf') or [])
    for moment in _find(spec, 'moments'):
        if moment.get('event'):
            names.add(moment['event'])
    for group in spec.get('funnels', []):
        for step in group.get('steps', []):
            if step.get('event'):
                names.add(step['event'])
            names.update(step.get('anyOf') or [])
    mon = spec.get('monetization') or {}
    for slot in ('tappedEvent', 'purchasedEvent'):
        if mon.get(slot):
            names.add(mon[slot])
    for card in spec.get('cards', []):
        for slot in ('tappedEvent', 'purchasedEvent'):
            if card.get(slot):
                names.add(card[slot])
    return {n.split(':', 1)[0] for n in names}


def internal_problems(spec: dict) -> list:
    """앱을 안 봐도 아는 것들 — 스펙 혼자서 앞뒤가 안 맞는 자리. 100% 확실하다."""
    found = []
    blob = json.dumps(spec, ensure_ascii=False)

    defined = {d['name'] for d in spec.get('derived', []) if 'name' in d}
    used = set(re.findall(r'"derived"\s*:\s*"([^"]+)"', blob))
    # `difference` 의 from/subtract 도 다른 파생값을 가리킬 수 있다.
    # 이걸 안 세면 멀쩡히 쓰이는 값이 "아무도 안 씁니다" 로 잡힌다.
    for d in spec.get('derived', []):
        for slot in ('from', 'subtract'):
            if d.get(slot) in defined:
                used.add(d[slot])
    for name in sorted(used - defined):
        found.append(f'derived "{name}" 를 쓰는데 정의가 없습니다')
    for name in sorted(defined - used):
        found.append(f'derived "{name}" 를 정의했는데 아무도 안 씁니다')

    segments = {r['name'] for c in spec.get('cards', [])
                if c.get('kind') == 'segments' for r in c.get('rules', [])}
    segments |= {r['name'] for r in (spec.get('segments') or {}).get('rules', [])}
    for name in sorted(set(re.findall(r'"segment"\s*:\s*"([^"]+)"', blob)) - segments):
        found.append(f'타일이 무리 "{name}" 를 가리키는데 그런 규칙이 없습니다')
    return found
