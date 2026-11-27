#!/usr/bin/env python3
"""2주에 한 번 배포 캘린더 — 앱마다 2주 안의 정해진 평일 하나를 준다.

평일 10일(월~금 × 2주)에 앱을 고르게 나눠, 하루에 너덧 개씩만 DeployBar 에 맡긴다.
같은 앱의 다른 플랫폼(맥 · 리모컨)은 본 앱과 같은 날에 낸다.
사용자가 많은 앱은 서로 다른 날로 흩어 한 날에 몰리지 않게 한다.

    python3 scripts/deploy-calendar.py            # ~/Documents/workspace/Auto/docs/deploy-calendar.ics
    open ~/Documents/workspace/Auto/docs/deploy-calendar.ics   # 캘린더 앱으로 가져오기

앱 목록은 `DeployBar --ready` 에서 읽는다. 앱이 늘거나 줄면 다시 돌려 가져오면 된다
(UID 가 날짜로 정해져 있어 같은 일정을 덮어쓴다).
"""
import datetime as dt
import os
import re
import subprocess
import unicodedata

DEPLOYBAR = '/Applications/DeployBar.app/Contents/MacOS/DeployBar'
OUT = os.path.expanduser('~/Documents/workspace/Auto/docs/deploy-calendar.ics')
START = dt.date(2026, 11, 30)   # 첫 주기의 월요일
HOUR = 10                       # 오전 10시 — 심사가 그날 안에 시작되게

# 다른 플랫폼은 본 앱과 같은 날에.
COMPANIONS = {'탭클립키보드': '클립키보드', 'YeoulMac': '여울', 'StickyPresenterRemote': 'StickyPresenter'}
# 사용자가 많은 앱 — 먼저 서로 다른 날에 하나씩 놓는다.
BIG = ['장표스냅', '인생맛집', '모찌모', '세끼', '클립키보드']


def apps():
    # DeployBar 는 폴더 이름을 NFD 로 내보내기도 한다 — 이름을 견주려면 NFC 로 맞춘다.
    out = subprocess.run([DEPLOYBAR, '--ready'], capture_output=True, text=True, timeout=120).stdout
    names = [unicodedata.normalize('NFC', m.group(1).strip()) for m in re.finditer(r'^\S+ (.+?) — ', out, re.M)]
    return list(dict.fromkeys(names))


def schedule(names):
    days = [START + dt.timedelta(days=w * 7 + d) for w in range(2) for d in range(5)]
    slots = {day: [] for day in days}
    main = [n for n in names if n not in COMPANIONS]
    ordered = [n for n in BIG if n in main] + [n for n in main if n not in BIG]
    for i, name in enumerate(ordered):
        slots[days[i % len(days)]].append(name)
    for extra, host in COMPANIONS.items():
        if extra in names:
            day = next((d for d, ns in slots.items() if host in ns), days[0])
            slots[day].append(extra)
    return slots


def ics(slots):
    stamp = dt.datetime.utcnow().strftime('%Y%m%dT%H%M%SZ')
    lines = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Leeo//Deploy Calendar//KO',
             'CALSCALE:GREGORIAN', 'X-WR-CALNAME:앱 배포 (2주)']
    for day, names in slots.items():
        if not names:
            continue
        notes = '\\n'.join(f'{DEPLOYBAR.rsplit("/", 1)[-1]} --deploy {n} --bump patch' for n in names)
        lines += ['BEGIN:VEVENT',
                  f'UID:deploy-{day:%a}-{(day - START).days // 7}@leeo',
                  f'DTSTAMP:{stamp}',
                  f'DTSTART;TZID=Asia/Seoul:{day:%Y%m%d}T{HOUR:02d}0000',
                  f'DTEND;TZID=Asia/Seoul:{day:%Y%m%d}T{HOUR:02d}3000',
                  'RRULE:FREQ=WEEKLY;INTERVAL=2',
                  f'SUMMARY:배포 · {" · ".join(names)}',
                  f'DESCRIPTION:{notes}',
                  'BEGIN:VALARM', 'ACTION:DISPLAY', 'DESCRIPTION:오늘 배포할 앱', 'TRIGGER:-PT0M', 'END:VALARM',
                  'END:VEVENT']
    lines.append('END:VCALENDAR')
    return '\r\n'.join(lines) + '\r\n'


if __name__ == '__main__':
    slots = schedule(apps())
    with open(OUT, 'w') as f:
        f.write(ics(slots))
    for day, names in slots.items():
        print(f'{day:%m/%d %a}  {" · ".join(names)}')
    print(OUT)
