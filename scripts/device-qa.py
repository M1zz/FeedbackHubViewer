#!/usr/bin/env python3
"""연결한 아이폰에서 workspace/Auto 의 앱들을 하나씩 테스트하고 품질 탭이 읽을 파일을 쓴다.

앱마다 차례로(동시에 하나만):
  1. 아이폰용 build-for-testing (테스트가 없는 스킴이면 build)
  2. 단위 · UI 테스트 (test-without-building) → xcresult 에서 통과 · 실패를 센다
  3. 설치하고 켠 뒤 몇 초 살아 있는지 본다

결과: <Auto>/docs/quality-tests.json — 허브 품질 탭의 "기기 테스트" 줄(`DeviceTests.swift`).
한 앱이 끝날 때마다 파일을 고쳐 쓰니 중간에 멈춰도 그때까지의 결과가 남는다.

    scripts/device-qa.py --device <UDID> [앱 폴더 이름 ...]
"""
import argparse, datetime, glob, json, os, plistlib, re, shutil, subprocess, sys, tempfile, time

AUTO = os.path.expanduser("~/Documents/workspace/Auto")
OUT = os.path.join(AUTO, "docs", "quality-tests.json")
WORK = os.environ.get("DEVICE_QA_WORK") or os.path.join(tempfile.gettempdir(), "device-qa")
# 레포에 Xcode 프로젝트가 여럿이면 iOS 앱이 든 것.
PROJECT_OVERRIDE = {"클립키보드": "ClipKeyboard.xcodeproj"}
SKIP_SCHEME = re.compile(r"widget|extension|tests?$|watch|mac|intent|keyboard$|share|notification|clip$", re.I)


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


def pick_scheme(project):
    code, out = run(["xcodebuild", "-list", "-json", "-project", project], 120)
    try:
        info = json.loads(out[out.index("{"):])["project"]
    except Exception:
        return None
    schemes = info.get("schemes", [])
    base = os.path.splitext(os.path.basename(project))[0]
    if base in schemes:
        return base
    plain = [s for s in schemes if not SKIP_SCHEME.search(s)]
    return (plain or schemes or [None])[0]


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


def built_app(dd):
    apps = [a for a in glob.glob(os.path.join(dd, "Build/Products/*-iphoneos/*.app"))
            if not a.endswith("-Runner.app")]
    # 앱 클립도 같은 자리에 나온다 — 클립의 번들 id 로 적으면 허브가 그 앱을 못 찾는다.
    return next((a for a in apps if not is_app_clip(a)), apps[0] if apps else None)


def is_app_clip(app):
    try:
        with open(os.path.join(app, "Info.plist"), "rb") as f:
            return "NSAppClip" in plistlib.load(f)
    except Exception:
        return False


def bundle_ids(app):
    ids = []
    for plist in [os.path.join(app, "Info.plist")] + glob.glob(os.path.join(app, "PlugIns/*.appex/Info.plist")):
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
        with open(os.path.join(app, "Info.plist"), "rb") as f:
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


def test_app(folder, device, packages):
    result = {"folder": folder, "bundleIDs": [], "testedAt": now_iso(), "version": None,
              "built": False, "launched": None, "unit": None, "ui": None, "failures": []}
    project = find_project(folder)
    if not project:
        result["failures"] = ["Xcode 프로젝트 없음"]
        return result
    scheme = pick_scheme(project)
    if not scheme:
        result["failures"] = ["스킴을 찾지 못함"]
        return result
    log(f"   프로젝트 {os.path.basename(project)} · 스킴 {scheme}")

    dd = os.path.join(WORK, "dd", re.sub(r"\W", "_", folder))
    shutil.rmtree(dd, ignore_errors=True)
    common = ["xcodebuild", "-project", project, "-scheme", scheme, "-destination", f"id={device}",
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

    app = built_app(dd)
    if app:
        result["bundleIDs"] = bundle_ids(app)
        result["version"] = app_version(app)

    if has_tests:
        log("   단위 · UI 테스트")
        xcresult = os.path.join(WORK, "results", re.sub(r"\W", "_", folder) + ".xcresult")
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
        ok, why = smoke_launch(device, app, result["bundleIDs"][0])
        result["launched"] = ok
        if why:
            result["failures"].insert(0, why)

    shutil.rmtree(dd, ignore_errors=True)
    return result


def save(entry, device_name):
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    try:
        with open(OUT, encoding="utf-8") as f:
            report = json.load(f)
    except Exception:
        report = {"apps": []}
    report["apps"] = [a for a in report.get("apps", []) if a.get("folder") != entry["folder"]] + [entry]
    report["apps"].sort(key=lambda a: a["folder"])
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
    parser.add_argument("--device", required=True)
    parser.add_argument("apps", nargs="*")
    args = parser.parse_args()

    folders = args.apps or sorted(
        d for d in os.listdir(AUTO)
        if os.path.isdir(os.path.join(AUTO, d)) and glob.glob(os.path.join(AUTO, d, "*.xcodeproj")))
    packages = os.path.join(WORK, "SourcePackages")
    os.makedirs(packages, exist_ok=True)
    name = device_name(args.device)
    log(f"{len(folders)}개 앱 · {name}")
    for i, folder in enumerate(folders, 1):
        log(f"── {folder} ({i}/{len(folders)})")
        entry = test_app(folder, args.device, packages)
        save(entry, name)
        unit, ui = entry["unit"] or {}, entry["ui"] or {}
        log(f"   결과: 빌드 {'O' if entry['built'] else 'X'} · 켜짐 {entry['launched']} · "
            f"단위 {unit.get('passed', '-')}/{unit.get('failed', '-')} · UI {ui.get('passed', '-')}/{ui.get('failed', '-')}"
            + (f" · {entry['failures'][0]}" if entry["failures"] else ""))
    log("끝")


if __name__ == "__main__":
    main()
