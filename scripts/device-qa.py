#!/usr/bin/env python3
"""workspace/Auto 의 앱들을 **플랫폼마다 따로** 테스트하고 품질 탭이 읽을 파일을 쓴다.

앱이 지원하는 애플 플랫폼(iOS · macOS · watchOS · visionOS · tvOS)을 스킴의 빌드 설정
(`SUPPORTED_PLATFORMS`)으로 찾고, 플랫폼마다 차례로(동시에 하나만):
  1. build-for-testing (테스트가 없는 스킴이면 build)
  2. 단위 · UI 테스트 (test-without-building) → xcresult 에서 통과 · 실패를 센다
  3. 설치하고 켠 뒤 몇 초 살아 있는지 본다

어디서 돌리나: iOS 는 연결한 아이폰(--device, 없으면 iPhone 시뮬레이터), macOS 는 이 맥,
watchOS · visionOS · tvOS 는 그 플랫폼의 시뮬레이터.

결과: <Auto>/docs/quality-tests.json — 허브 품질 탭의 "기기 테스트" 줄(`DeviceTests.swift`).
줄마다 "platform" 이 있고 (폴더, 플랫폼) 하나에 한 줄이다. 한 플랫폼이 끝날 때마다 파일을 고쳐
쓰니 중간에 멈춰도 그때까지의 결과가 남는다.

    scripts/device-qa.py [--device <UDID>] [--platforms iOS,macOS] [앱 폴더 이름 ...]
"""
import argparse, datetime, glob, json, os, plistlib, re, shutil, subprocess, sys, tempfile, time, unicodedata

AUTO = os.path.expanduser("~/Documents/workspace/Auto")
OUT = os.path.join(AUTO, "docs", "quality-tests.json")
WORK = os.environ.get("DEVICE_QA_WORK") or os.path.join(tempfile.gettempdir(), "device-qa")
# 레포에 Xcode 프로젝트가 여럿이면 iOS 앱이 든 것.
PROJECT_OVERRIDE = {"클립키보드": "ClipKeyboard.xcodeproj"}
SKIP_SCHEME = re.compile(r"widget|extension|tests?$|watch|mac|intent|keyboard$|share|notification|clip$", re.I)
# 플랫폼만 다른 스킴(…Mac · …Watch)은 그 플랫폼을 고를 때 후보가 된다.
EXTENSION_SCHEME = re.compile(r"widget|extension|tests?$|intent|keyboard$|share|notification|clip$", re.I)

# SUPPORTED_PLATFORMS 의 SDK 이름 → 허브가 쓰는 플랫폼 이름. 차례가 곧 테스트 차례.
PLATFORMS = [("iphoneos", "iOS"), ("macosx", "macOS"), ("watchos", "watchOS"), ("xros", "visionOS"), ("appletvos", "tvOS")]
# 빌드 결과가 놓이는 폴더 꼬리(Build/Products/Debug-<꼬리>). macOS 는 꼬리가 없다.
PRODUCT_SUFFIX = {"iOS-device": "-iphoneos", "iOS-sim": "-iphonesimulator", "macOS": "",
                  "watchOS": "-watchsimulator", "visionOS": "-xrsimulator", "tvOS": "-appletvsimulator"}
SIM_RUNTIME = {"iOS": "iOS", "watchOS": "watchOS", "visionOS": "xrOS", "tvOS": "tvOS"}
APP_TYPES = ("com.apple.product-type.application", "com.apple.product-type.application.watchapp2",
             "com.apple.product-type.application.watchapp2-container")


def log(msg):
    print(msg, flush=True)


def run(cmd, timeout, cwd=None):
    try:
        p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, errors="replace", timeout=timeout)
        return p.returncode, p.stdout + p.stderr
    except subprocess.TimeoutExpired as e:
        out = (e.stdout or b"").decode(errors="replace") if isinstance(e.stdout, bytes) else (e.stdout or "")
        return -9, out + f"\n시간 초과({timeout}초)"


def now_iso():
    return datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def find_project(folder):
    path = os.path.join(AUTO, folder)
    if folder in PROJECT_OVERRIDE:
        return os.path.join(path, PROJECT_OVERRIDE[folder])
    found = sorted(glob.glob(os.path.join(path, "*.xcodeproj")))
    return found[0] if found else None


def list_schemes(project):
    code, out = run(["xcodebuild", "-list", "-json", "-project", project], 120)
    try:
        return json.loads(out[out.index("{"):])["project"].get("schemes", [])
    except Exception:
        return []


def pick_scheme(project):
    schemes = list_schemes(project)
    base = os.path.splitext(os.path.basename(project))[0]
    if base in schemes:
        return base
    plain = [s for s in schemes if not SKIP_SCHEME.search(s)]
    return (plain or schemes or [None])[0]


def scheme_platforms(project, scheme):
    """이 스킴이 빌드하는 **앱** 대상들의 플랫폼. 확장 · 테스트 대상은 보지 않는다."""
    try:
        # 경고(여러 목적지 중 첫 것)는 stderr 로 온다 — JSON 은 stdout 만.
        out = subprocess.run(["xcodebuild", "-showBuildSettings", "-json", "-project", project, "-scheme", scheme],
                             capture_output=True, text=True, errors="replace", timeout=300).stdout
        targets = json.loads(out[out.index("["):])
    except Exception:
        return set()
    found = set()
    for target in targets:
        settings = target.get("buildSettings", {})
        if settings.get("PRODUCT_TYPE") not in APP_TYPES:
            continue
        supported = (settings.get("SUPPORTED_PLATFORMS") or settings.get("SDKROOT") or "").split()
        for sdk, name in PLATFORMS:
            if sdk in supported:
                found.add(name)
    return found


def platform_schemes(project):
    """플랫폼 → 그 플랫폼 앱을 빌드하는 스킴. 기본 스킴이 먼저, 없으면 …Mac · …Watch 같은 스킴."""
    base = pick_scheme(project)
    candidates = [base] + [s for s in list_schemes(project) if s != base and not EXTENSION_SCHEME.search(s)]
    chosen = {}
    for scheme in candidates:
        if not scheme:
            continue
        for platform in scheme_platforms(project, scheme):
            chosen.setdefault(platform, scheme)
        if len(chosen) == len(PLATFORMS):
            break
    return dict(sorted(chosen.items(), key=lambda kv: [n for _, n in PLATFORMS].index(kv[0])))


_simulators = None


def simulator(platform):
    """그 플랫폼의 쓸 수 있는 시뮬레이터 UDID — 가장 새 런타임의 첫 기기."""
    global _simulators
    if _simulators is None:
        code, out = run(["xcrun", "simctl", "list", "devices", "available", "-j"], 120)
        try:
            _simulators = json.loads(out[out.index("{"):]).get("devices", {})
        except Exception:
            _simulators = {}
    key = SIM_RUNTIME.get(platform)
    runtimes = sorted((r for r in _simulators if key and f".SimRuntime.{key}-" in r), reverse=True)
    for runtime in runtimes:
        devices = _simulators[runtime]
        if platform == "iOS":
            devices = [d for d in devices if "iPhone" in d.get("name", "")] or devices
        if devices:
            return devices[0]["udid"]
    return None


def first_error(text):
    for line in text.splitlines():
        if " error: " in line or line.startswith("error:") or "xcodebuild: error" in line:
            return re.sub(r"^.*?error:\s*", "", line).strip()[:200]
    tail = [l for l in text.strip().splitlines() if l.strip()]
    return (tail[-1][:200] if tail else "알 수 없는 이유")


def count_tests(xcresult):
    """대상(target) 이름에 UITests 가 들면 UI, 아니면 단위."""
    code, out = run(["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", xcresult], 120)
    unit = {"passed": 0, "failed": 0, "skipped": 0}
    ui = {"passed": 0, "failed": 0, "skipped": 0}
    seen_unit = seen_ui = False
    failures = []
    try:
        data = json.loads(out[out.index("{"):])
    except Exception:
        return None, None, ["테스트 결과를 읽지 못함"]

    def walk(node, target):
        nonlocal seen_unit, seen_ui
        kind = node.get("nodeType")
        if kind == "Unit test bundle" or kind == "UI test bundle":
            target = node.get("name", "")
        if kind == "Test Case":
            is_ui = "uitest" in (target or "").lower()
            bucket = ui if is_ui else unit
            if is_ui:
                seen_ui = True
            else:
                seen_unit = True
            result = node.get("result", "")
            if result == "Passed":
                bucket["passed"] += 1
            elif result == "Failed":
                bucket["failed"] += 1
                msg = ""
                for child in node.get("children", []) or []:
                    if child.get("nodeType") == "Failure Message":
                        msg = child.get("name", "")
                        break
                failures.append(f"{node.get('name', '')}: {msg}".strip(": ")[:200])
            else:
                bucket["skipped"] += 1
        for child in node.get("children", []) or []:
            walk(child, target)

    for node in data.get("testNodes", []):
        walk(node, None)
    return (unit if seen_unit else None), (ui if seen_ui else None), failures


def built_app(dd, suffix="-iphoneos"):
    apps = [a for a in glob.glob(os.path.join(dd, f"Build/Products/*{suffix}/*.app"))
            if not a.endswith("-Runner.app")]
    if suffix == "":
        # macOS 는 꼬리 없는 폴더(Debug/) — 다른 플랫폼 폴더(Debug-iphoneos/)는 뺀다.
        apps = [a for a in apps if "-" not in os.path.basename(os.path.dirname(a))]
    # 앱 클립도 같은 자리에 나온다 — 클립의 번들 id 로 적으면 허브가 그 앱을 못 찾는다.
    return next((a for a in apps if not is_app_clip(a)), apps[0] if apps else None)


def info_plist(app):
    """iOS · 시뮬레이터 앱은 바로 아래, 맥 앱은 Contents/ 아래."""
    mac = os.path.join(app, "Contents", "Info.plist")
    return mac if os.path.exists(mac) else os.path.join(app, "Info.plist")


def is_app_clip(app):
    try:
        with open(info_plist(app), "rb") as f:
            return "NSAppClip" in plistlib.load(f)
    except Exception:
        return False


def bundle_ids(app):
    ids = []
    plugins = glob.glob(os.path.join(app, "PlugIns/*.appex/Info.plist")) + \
        glob.glob(os.path.join(app, "Contents/PlugIns/*.appex/Contents/Info.plist"))
    for plist in [info_plist(app)] + plugins:
        try:
            with open(plist, "rb") as f:
                ids.append(plistlib.load(f)["CFBundleIdentifier"])
        except Exception:
            pass
    return ids


def project_bundle_ids(project):
    with open(os.path.join(project, "project.pbxproj"), encoding="utf-8", errors="replace") as f:
        found = re.findall(r'PRODUCT_BUNDLE_IDENTIFIER = "?([A-Za-z0-9.\-]+)"?;', f.read())
    return sorted({b for b in found if not re.search(r"(?i)tests?$", b)})


def app_version(app):
    try:
        with open(info_plist(app), "rb") as f:
            return plistlib.load(f).get("CFBundleShortVersionString")
    except Exception:
        return None


def smoke_launch(device, app, bundle_id):
    """설치하고 켠 뒤 8초 지나도 떠 있으면 켜진 것."""
    code, out = run(["xcrun", "devicectl", "device", "install", "app", "--device", device, app], 600)
    if code != 0:
        return False, "설치 실패: " + first_error(out)
    code, out = run(["xcrun", "devicectl", "device", "process", "launch", "--device", device,
                     "--terminate-existing", bundle_id], 120)
    if code != 0:
        return False, "켜기 실패: " + first_error(out)
    time.sleep(8)
    exe = os.path.basename(app)[:-4]
    code, out = run(["xcrun", "devicectl", "device", "info", "processes", "--device", device], 120)
    alive = f"/{os.path.basename(app)}/" in out or exe in out
    if not alive:
        return False, "켠 뒤 8초 안에 꺼짐(크래시 의심)"
    return True, None


def smoke_launch_mac(app):
    """맥에서 켠 뒤 8초 지나도 떠 있으면 켜진 것. 본 뒤 끈다."""
    exe_dir = os.path.join(app, "Contents", "MacOS")
    code, out = run(["open", "-n", "-g", app], 60)
    if code != 0:
        return False, "켜기 실패: " + first_error(out)
    time.sleep(8)
    # pgrep -f 는 한글 경로의 NFC · NFD 가 다르면 못 찾는다 — 둘 다 NFC 로 맞춰 견준다.
    want = unicodedata.normalize("NFC", exe_dir)
    code, out = run(["ps", "-axo", "pid=,command="], 30)
    pids = [line.split(None, 1)[0] for line in out.splitlines()
            if len(line.split(None, 1)) == 2 and want in unicodedata.normalize("NFC", line.split(None, 1)[1])]
    for pid in pids:
        run(["kill", pid], 10)
    return (True, None) if pids else (False, "켠 뒤 8초 안에 꺼짐(크래시 의심)")


def smoke_launch_sim(udid, app, bundle_id):
    """시뮬레이터에 설치하고 켠 뒤 8초 지나도 떠 있으면 켜진 것. 시뮬레이터 앱은 이 맥의 프로세스다."""
    run(["xcrun", "simctl", "boot", udid], 300)
    run(["xcrun", "simctl", "bootstatus", udid, "-b"], 600)
    code, out = run(["xcrun", "simctl", "install", udid, app], 600)
    if code != 0:
        return False, "설치 실패: " + first_error(out)
    code, out = run(["xcrun", "simctl", "launch", "--terminate-running-process", udid, bundle_id], 120)
    pid = re.search(r":\s*(\d+)\s*$", out.strip())
    if code != 0 or not pid:
        return False, "켜기 실패: " + first_error(out)
    time.sleep(8)
    try:
        os.kill(int(pid.group(1)), 0)
    except OSError:
        return False, "켠 뒤 8초 안에 꺼짐(크래시 의심)"
    run(["xcrun", "simctl", "terminate", udid, bundle_id], 60)
    return True, None


def test_app(folder, device, packages, platform="iOS", scheme=None, project=None):
    result = {"folder": folder, "platform": platform, "bundleIDs": [], "testedAt": now_iso(), "version": None,
              "built": False, "launched": None, "unit": None, "ui": None, "failures": []}
    project = project or find_project(folder)
    if not project:
        result["failures"] = ["Xcode 프로젝트 없음"]
        return result
    scheme = scheme or pick_scheme(project)
    if not scheme:
        result["failures"] = ["스킴을 찾지 못함"]
        return result

    # 어디서 돌리나 — 아이폰 · 이 맥 · 시뮬레이터.
    if platform == "iOS" and device:
        destination, suffix, where = f"id={device}", PRODUCT_SUFFIX["iOS-device"], "device"
    elif platform == "macOS":
        destination, suffix, where = "platform=macOS", PRODUCT_SUFFIX["macOS"], "mac"
    else:
        udid = simulator(platform)
        if not udid:
            result["failures"] = [f"{platform} 시뮬레이터 없음 — Xcode ▸ Settings ▸ Components 에서 받기"]
            return result
        destination, where = f"id={udid}", "sim"
        suffix = PRODUCT_SUFFIX["iOS-sim" if platform == "iOS" else platform]
    log(f"   [{platform}] 프로젝트 {os.path.basename(project)} · 스킴 {scheme} · {destination}")

    dd = os.path.join(WORK, "dd", re.sub(r"\W", "_", folder) + "-" + platform)
    shutil.rmtree(dd, ignore_errors=True)
    common = ["xcodebuild", "-project", project, "-scheme", scheme, "-destination", destination,
              "-derivedDataPath", dd, "-clonedSourcePackagesDirPath", packages,
              "-allowProvisioningUpdates", "-skipMacroValidation", "-skipPackagePluginValidation"]

    log("   빌드 (테스트 포함)")
    # 커버리지를 켜고 빌드 · 실행한다 — 같은 xcresult 를 test-coverage.py 가 읽어 품질 탭 커버리지가 된다.
    code, out = run(common + ["build-for-testing", "-enableCodeCoverage", "YES"], 1800)
    has_tests = code == 0
    if code != 0:
        # 테스트 대상만 못 빌드해도(서명 · 테스트 없는 스킴) 앱은 켜 본다.
        log("   테스트 빌드 못 함 — 앱만 빌드")
        code, out = run(common + ["build"], 1800)
    if code != 0:
        result["failures"] = [first_error(out)]
        # 빌드를 못 해도 어느 앱인지는 적는다 — 번들 id 가 비면 허브가 "빌드 못 함" 을 어느 앱에도 못 붙인다.
        result["bundleIDs"] = project_bundle_ids(project)
        shutil.rmtree(dd, ignore_errors=True)
        return result
    result["built"] = True

    app = built_app(dd, suffix)
    if app:
        result["bundleIDs"] = bundle_ids(app)
        result["version"] = app_version(app)

    if has_tests:
        log("   단위 · UI 테스트")
        # iOS 는 예전 이름 그대로 — test-coverage.py 가 같은 자리를 본다.
        stem = re.sub(r"\W", "_", folder) + ("" if platform == "iOS" else "-" + platform)
        xcresult = os.path.join(WORK, "results", stem + ".xcresult")
        shutil.rmtree(xcresult, ignore_errors=True)
        code, out = run(common + ["test-without-building", "-enableCodeCoverage", "YES", "-resultBundlePath", xcresult,
                                  "-test-timeouts-enabled", "YES", "-maximum-test-execution-time-allowance", "300"], 2700)
        if os.path.exists(xcresult):
            unit, ui, failures = count_tests(xcresult)
            result["unit"], result["ui"] = unit, ui
            result["failures"] += failures
        if code != 0 and ("not currently configured for the test" in out or "Cannot test target" in out):
            pass  # 스킴에 테스트가 없거나 이 기기에서 못 돌리는 테스트 — 앱의 실패가 아니다
        elif code != 0 and not result["failures"]:
            result["failures"].append("테스트 실행 실패: " + first_error(out))
            result["unit"] = result["unit"] or {"passed": 0, "failed": 1, "skipped": 0}

    if app and result["bundleIDs"]:
        log("   설치하고 켜 보기")
        if where == "device":
            ok, why = smoke_launch(device, app, result["bundleIDs"][0])
        elif where == "mac":
            ok, why = smoke_launch_mac(app)
        else:
            ok, why = smoke_launch_sim(destination[3:], app, result["bundleIDs"][0])
        result["launched"] = ok
        if why:
            result["failures"].insert(0, why)

    shutil.rmtree(dd, ignore_errors=True)
    return result


def save(entry, device_name):
    entry["folder"] = unicodedata.normalize("NFC", entry["folder"])
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    try:
        with open(OUT, encoding="utf-8") as f:
            report = json.load(f)
    except Exception:
        report = {"apps": []}
    key = (entry["folder"], entry.get("platform") or "iOS")
    report["apps"] = [a for a in report.get("apps", [])
                      if (unicodedata.normalize("NFC", a.get("folder", "")), a.get("platform") or "iOS") != key] + [entry]
    report["apps"].sort(key=lambda a: (a["folder"], a.get("platform") or "iOS"))
    report["generatedAt"] = now_iso()
    report["device"] = device_name
    tmp = OUT + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=2)
    os.replace(tmp, OUT)


def device_name(device):
    code, out = run(["xcrun", "devicectl", "list", "devices"], 60)
    for line in out.splitlines():
        if device in line:
            model = re.search(r"(iPhone[^()]*|iPad[^()]*)\(", line)
            return (model.group(1).strip() if model else "iPhone")
    return "iPhone"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--device", help="연결한 아이폰 UDID. 없으면 iOS 는 iPhone 시뮬레이터에서")
    parser.add_argument("--platforms", help="이 플랫폼만(쉼표로) — 예: iOS,macOS. 없으면 앱이 지원하는 전부")
    parser.add_argument("apps", nargs="*")
    args = parser.parse_args()
    only = {p.strip().lower() for p in args.platforms.split(",")} if args.platforms else None

    folders = args.apps or sorted(
        d for d in os.listdir(AUTO)
        if os.path.isdir(os.path.join(AUTO, d)) and glob.glob(os.path.join(AUTO, d, "*.xcodeproj")))
    packages = os.path.join(WORK, "SourcePackages")
    os.makedirs(packages, exist_ok=True)
    name = device_name(args.device) if args.device else "시뮬레이터"
    log(f"{len(folders)}개 앱 · {name}")
    for i, folder in enumerate(folders, 1):
        log(f"── {folder} ({i}/{len(folders)})")
        project = find_project(folder)
        targets = platform_schemes(project) if project else {}
        if not targets:
            # 플랫폼을 못 읽었으면(빌드 설정을 못 냄) 예전처럼 iOS 하나로 — 결과에 이유가 남는다.
            targets = {"iOS": pick_scheme(project) if project else None}
        log(f"   플랫폼: {', '.join(f'{p}({s})' for p, s in targets.items())}")
        for platform, scheme in targets.items():
            if only and platform.lower() not in only:
                continue
            entry = test_app(folder, args.device, packages, platform=platform, scheme=scheme, project=project)
            save(entry, name)
            unit, ui = entry["unit"] or {}, entry["ui"] or {}
            log(f"   [{platform}] 결과: 빌드 {'O' if entry['built'] else 'X'} · 켜짐 {entry['launched']} · "
                f"단위 {unit.get('passed', '-')}/{unit.get('failed', '-')} · UI {ui.get('passed', '-')}/{ui.get('failed', '-')}"
                + (f" · {entry['failures'][0]}" if entry["failures"] else ""))
    log("끝")


if __name__ == "__main__":
    main()
