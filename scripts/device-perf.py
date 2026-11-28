#!/usr/bin/env python3
"""기기에서 실행 속도 · 멈춤을 재어 quality-tests.json 의 각 줄에 "perf" 로 싣는다.

사용자 기기의 MetricKit 값이 아직 없는 앱도 품질 탭이 비지 않게 하는 실험실 값이다.
device-qa.py 가 먼저 돌아 앱이 깔려 있어야 한다(iOS 는 아이폰, macOS 는 이 맥에 깔린 것).

앱마다 Instruments(xctrace) "App Launch" + "Hangs" 로 RUNS 번 켜서:
  launchMs    켜기 시작 ~ 첫 화면(Foreground - Active)까지, 가운데 값
  hangPerHour 기록한 시간 동안 멈춘 초를 한 시간으로 늘린 값(250ms 넘는 멈춤만 잡힌다)

    scripts/device-perf.py --device <UDID> [앱 폴더 이름 ...]
"""
import argparse, datetime, fcntl, json, os, re, shutil, statistics, subprocess, tempfile, time, unicodedata
import xml.etree.ElementTree as ET

AUTO = os.path.expanduser("~/Documents/workspace/Auto")
OUT = os.path.join(AUTO, "docs", "quality-tests.json")
WORK = os.environ.get("DEVICE_QA_WORK") or os.path.join(tempfile.gettempdir(), "device-qa")
RUNS = 3
SECONDS = 20
# App Launch(시간 프로파일 · 스레드 상태까지 담는 무거운 틀)는 기록 시간에 비례해 커진다 — 20초면 5GB 를
# 넘긴 적이 있다. 첫 화면은 1초 안에 오니 짧게 찍고, 멈춤은 가벼운 Hangs 만 SECONDS 동안 따로 찍는다.
LAUNCH_SECONDS = 5
MIN_FREE_GB = 3


def log(msg):
    print(msg, flush=True)


def run(cmd, timeout):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, errors="replace", timeout=timeout)
        return p.returncode, p.stdout + p.stderr
    except subprocess.TimeoutExpired:
        return -9, f"시간 초과({timeout}초)"


def table(trace, schema):
    """xctrace 표를 행 목록으로. id/ref 로 줄인 값을 풀어 열 이름 → (글자, 숫자)."""
    code, out = run(["xcrun", "xctrace", "export", "--input", trace, "--xpath",
                     f'/trace-toc/run[@number="1"]/data/table[@schema="{schema}"]'], 300)
    try:
        root = ET.fromstring(out[out.index("<?xml"):])
    except Exception:
        return []
    node = root.find("node")
    if node is None:
        return []
    cols = [c.findtext("mnemonic") for c in node.find("schema").findall("col")]
    seen, rows = {}, []
    for row in node.findall("row"):
        values = []
        for el in row:
            if "ref" in el.attrib:
                el = seen.get(el.attrib["ref"], el)
            if "id" in el.attrib:
                seen[el.attrib["id"]] = el
            values.append((el.attrib.get("fmt", ""), el.text))
        rows.append(dict(zip(cols, values)))
    return rows


def record(target, device, out, launch_template=True):
    free_gb = shutil.disk_usage(WORK).free / 1e9
    if free_gb < MIN_FREE_GB:
        raise SystemExit(f"디스크 남은 공간 {free_gb:.1f}GB — {MIN_FREE_GB}GB 아래라 멈춤")
    cmd = ["xcrun", "xctrace", "record"]
    if launch_template:
        cmd += ["--template", "App Launch", "--time-limit", f"{LAUNCH_SECONDS}s"]
    else:
        cmd += ["--instrument", "Hangs", "--time-limit", f"{SECONDS}s"]
    cmd += ["--output", out]
    if device:
        cmd += ["--device", device]
    code, text = run(cmd + ["--launch", "--", target], 300)
    sweep_ktrace()
    return os.path.exists(out), text


def sweep_ktrace():
    """Instruments 가 임시 폴더에 남기는 커널 기록(instruments*.ktrace)을 치운다.
    맥 앱 App Launch 는 한 번에 2~4GB 라, 끊긴 기록이 쌓여 디스크를 채운 적이 있다(2026-11-28, 39GB).
    다른 측정(아이폰 · 맥을 함께 돌릴 때)이 쓰는 중이면 계속 고쳐지니, 1분 넘게 안 바뀐 것만 지운다."""
    folder = os.environ.get("TMPDIR") or tempfile.gettempdir()
    now = time.time()
    # xctrace 가 프로세스마다 만드는 임시 저장소(…/C/com.apple.dt.InstrumentsCLI/path_manager/xrtmp__<pid>.*).
    # 끝난 프로세스의 것만 지운다.
    manager = os.path.join(os.path.dirname(folder.rstrip("/")), "C", "com.apple.dt.InstrumentsCLI", "path_manager")
    for name in (os.listdir(manager) if os.path.isdir(manager) else []):
        m = re.match(r"xrtmp__(\d+)\.", name)
        if m and subprocess.run(["kill", "-0", m.group(1)], capture_output=True).returncode != 0:
            shutil.rmtree(os.path.join(manager, name), ignore_errors=True)
    for name in os.listdir(folder):
        path = os.path.join(folder, name)
        if name.startswith("instruments") and name.endswith(".ktrace"):
            try:
                if now - os.path.getmtime(path) > 60:
                    os.remove(path)
            except OSError:
                pass


def trace_hangs(trace):
    total = 0.0
    for r in table(trace, "potential-hangs"):
        if r.get("duration") and r["duration"][1]:
            total += int(r["duration"][1]) / 1e9
    return total


def fresh_trace(stem, i):
    trace = os.path.join(WORK, "perf", f"{stem}-{i}.trace")
    subprocess.run(["rm", "-rf", trace])
    os.makedirs(os.path.dirname(trace), exist_ok=True)
    return trace


def check_disk(ok, text):
    if not ok and "Cannot create output document" in text:
        raise SystemExit("trace 를 쓸 수 없음 — 디스크가 찼는지 보세요")
    if not ok:
        log(f"   기록 실패: {text.strip().splitlines()[-1] if text.strip() else '?'}")


def result(launches, hang_seconds, recorded):
    if not launches:
        return None
    return {"launchMs": round(statistics.median(launches)),
            "hangPerHour": round(hang_seconds / recorded * 3600, 1) if recorded else None,
            "samples": len(launches), "seconds": recorded,
            "measuredAt": datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")}


def measure(target, device, stem):
    """아이폰: App Launch 를 짧게 RUNS 번 찍어 첫 화면(Foreground - Active)까지, 멈춤은 Hangs 만 한 번."""
    launches = []
    for i in range(RUNS):
        trace = fresh_trace(stem, i)
        ok, text = record(target, device, trace)
        check_disk(ok, text)
        if not ok:
            continue
        periods = table(trace, "life-cycle-period")
        starts = [int(r["start"][1]) for r in periods if r.get("start") and r["start"][1]]
        active = [int(r["start"][1]) for r in periods
                  if r.get("period") and r["period"][0].startswith("Foreground") and r["start"][1]]
        if starts and active:
            launches.append((min(active) - min(starts)) / 1e6)
        subprocess.run(["rm", "-rf", trace])
    trace = fresh_trace(stem, "hang")
    ok, text = record(target, device, trace, launch_template=False)
    check_disk(ok, text)
    hang_seconds = trace_hangs(trace) if ok else 0.0
    subprocess.run(["rm", "-rf", trace])
    return result(launches, hang_seconds, SECONDS if ok else 0)


def mac_timer():
    """맥 첫 창까지의 시간을 재는 작은 도구를 한 번 컴파일한다."""
    binary = os.path.join(WORK, "mac-launch-time")
    source = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mac-launch-time.swift")
    if not os.path.exists(binary) or os.path.getmtime(binary) < os.path.getmtime(source):
        os.makedirs(WORK, exist_ok=True)
        code, text = run(["xcrun", "swiftc", "-O", source, "-o", binary], 600)
        if code != 0:
            raise SystemExit("mac-launch-time 컴파일 실패: " + text[-300:])
    return binary


def measure_mac(app, stem):
    """맥: App Launch 는 맥에서 첫 화면 단계를 남기지 않는다 — 켠 뒤 첫 창까지를 직접 재고, 멈춤은 Hangs 만."""
    timer = mac_timer()
    launches = []
    for _ in range(RUNS):
        code, out = run([timer, app], 60)
        if code == 0 and out.strip().splitlines()[-1].isdigit():
            launches.append(float(out.strip().splitlines()[-1]))
        time.sleep(2)
    trace = fresh_trace(stem, 0)
    ok, text = record(app, None, trace, launch_template=False)
    check_disk(ok, text)
    hang_seconds = trace_hangs(trace) if ok else 0.0
    subprocess.run(["rm", "-rf", trace])
    run(["pkill", "-f", os.path.join(app, "Contents", "MacOS")], 10)
    return result(launches, hang_seconds, SECONDS if ok else 0)


def mac_app(bundle_id):
    code, out = run(["mdfind", f"kMDItemCFBundleIdentifier == '{bundle_id}'"], 60)
    # 맥 앱만 — 같은 번들 id 의 시뮬레이터 · 기기용 빌드(Debug-iphonesimulator 등)는 이 맥에서 켤 수 없다.
    apps = [p for p in out.splitlines() if p.endswith(".app") and "/DerivedData/" not in p and "/tmp/" not in p
            and not re.search(r"-(iphone|xr|watch|appletv)(os|simulator)/", p)
            and os.path.isdir(os.path.join(p, "Contents", "MacOS"))]
    apps.sort(key=lambda p: (not p.startswith("/Applications/"), len(p)))
    return apps[0] if apps else None


def save(folder, platform, perf):
    # 아이폰 · 맥 측정을 함께 돌리면 두 프로세스가 같은 파일을 고친다 — 읽고 쓰는 동안 잠근다.
    with open(OUT + ".lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        _save(folder, platform, perf)


def _save(folder, platform, perf):
    with open(OUT, encoding="utf-8") as f:
        report = json.load(f)
    for app in report["apps"]:
        if app["folder"] == folder and (app.get("platform") or "iOS") == platform:
            app["perf"] = perf
    tmp = OUT + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=2)
    os.replace(tmp, OUT)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--device", help="iOS 를 잴 아이폰 UDID")
    parser.add_argument("--platform", choices=["iOS", "macOS"],
                        help="이 플랫폼만 — 아이폰과 맥은 겹치지 않으니 둘을 따로 띄워 함께 돌려도 된다")
    parser.add_argument("apps", nargs="*")
    args = parser.parse_args()
    wanted = {unicodedata.normalize("NFC", a) for a in args.apps}

    with open(OUT, encoding="utf-8") as f:
        apps = json.load(f)["apps"]
    platforms = [args.platform] if args.platform else ["iOS", "macOS"]
    if "iOS" in platforms and not args.device:
        platforms.remove("iOS")  # 시뮬레이터로는 재지 않는다 — 실험실 값이라도 실제 기기여야 한다
    todo = [a for a in apps if (a.get("platform") or "iOS") in platforms and a.get("bundleIDs")
            and (not wanted or a["folder"] in wanted) and (wanted or not a.get("perf"))]
    log(f"{len(todo)}개 측정 · 앱마다 {RUNS}번 · {SECONDS}초씩")
    for i, app in enumerate(todo, 1):
        platform = app.get("platform") or "iOS"
        log(f"── {app['folder']} [{platform}] ({i}/{len(todo)})")
        bundle = app["bundleIDs"][0]
        if platform == "iOS":
            target, device = bundle, args.device
        else:
            target, device = mac_app(bundle), None
            if not target:
                log("   이 맥에 깔린 앱이 없어 건너뜀")
                continue
        stem = re.sub(r"\W", "_", app["folder"]) + "-" + platform
        perf = measure(target, device, stem) if platform == "iOS" else measure_mac(target, stem)
        if perf:
            save(app["folder"], platform, perf)
            log(f"   실행 {perf['launchMs']}ms · 멈춤 시간당 {perf['hangPerHour']}초 ({perf['samples']}번)")
        else:
            log("   재지 못함")
    log("끝")


if __name__ == "__main__":
    main()
