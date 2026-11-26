#!/usr/bin/env python3
"""workspace/Auto 의 앱마다 테스트 커버리지를 모아 품질 탭이 읽을 파일을 쓴다.

테스트를 새로 돌리지 않는다. 읽기만 한다:
  1. 실제 커버리지 — DerivedData 와 device-qa.py 결과 중 가장 새 .xcresult(`xcrun xccov view --report --json`).
     앱 · 확장(.app · .appex)의 줄 커버리지만 센다. 테스트 번들과 패키지(LeeoKit 등)는 뺀다.
  2. 없으면 정적 측정 — 테스트 함수 수(`func test…` · `@Test`) · 테스트 파일 · 소스 파일.
     커버리지가 아니라서 화면은 "커버리지 모름" 으로 적는다(테스트가 하나도 없으면 0%).

결과: <Auto>/docs/test-coverage.json — 허브 품질 탭의 "커버리지" 줄(`TestCoverage.swift`).
테스트를 돌릴 때 Xcode 의 Code Coverage 를 켜 두면(스킴 ▸ Test ▸ Options) 다음 실행부터 실제 값이 잡힌다.

    scripts/test-coverage.py
"""
import datetime, glob, json, os, plistlib, re, subprocess, tempfile

AUTO = os.path.expanduser("~/Documents/workspace/Auto")
OUT = os.path.join(AUTO, "docs", "test-coverage.json")
DERIVED = os.path.expanduser("~/Library/Developer/Xcode/DerivedData")
# device-qa.py 가 아이폰에서 커버리지를 켜고 돌린 결과(<WORK>/results/<폴더>.xcresult). 두 스크립트가 같은 자리를 본다.
DEVICE_QA_RESULTS = os.path.join(os.environ.get("DEVICE_QA_WORK") or os.path.join(tempfile.gettempdir(), "device-qa"), "results")
SKIP_DIRS = {".git", ".build", "build", "DerivedData", "Pods", "node_modules", "fastlane", "docs"}
TEST_FUNC = re.compile(r"^\s*(?:@Test\b|(?:@\w+\s+)*func\s+test\w*\s*\()", re.M)
TEST_IMPORT = re.compile(r"^\s*(?:@testable\s+)?import\s+(?:XCTest|Testing)\b", re.M)
BUNDLE_ID = re.compile(r"PRODUCT_BUNDLE_IDENTIFIER = \"?([A-Za-z0-9.\-]+)\"?;")


def iso(ts):
    return datetime.datetime.fromtimestamp(ts, datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def repos():
    """Xcode 프로젝트가 든 최상위 폴더."""
    for name in sorted(os.listdir(AUTO)):
        path = os.path.join(AUTO, name)
        if os.path.isdir(path) and not name.startswith(".") and glob.glob(os.path.join(path, "**", "*.xcodeproj"), recursive=True):
            yield name, path


def walk_swift(root):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS and not d.startswith(".") and not d.endswith((".xcodeproj", ".xcworkspace"))]
        for f in filenames:
            if f.endswith(".swift"):
                yield os.path.join(dirpath, f)


def bundle_ids(root):
    ids = set()
    for pbx in glob.glob(os.path.join(root, "**", "*.xcodeproj", "project.pbxproj"), recursive=True):
        with open(pbx, encoding="utf-8", errors="replace") as fh:
            for found in BUNDLE_ID.findall(fh.read()):
                if not re.search(r"(?i)tests?$", found):
                    ids.add(found)
    return sorted(ids)


def static_counts(root):
    tests = files = sources = 0
    for path in walk_swift(root):
        with open(path, encoding="utf-8", errors="replace") as fh:
            text = fh.read()
        if TEST_IMPORT.search(text):
            files += 1
            tests += len(TEST_FUNC.findall(text))
        else:
            sources += 1
    return tests, files, sources


def xcresults_by_repo():
    """레포 경로 → 그 레포를 빌드한 DerivedData 의 xcresult 들(새것부터)."""
    found = {}
    for info in glob.glob(os.path.join(DERIVED, "*", "info.plist")):
        try:
            with open(info, "rb") as fh:
                workspace = plistlib.load(fh).get("WorkspacePath", "")
        except Exception:
            continue
        results = glob.glob(os.path.join(os.path.dirname(info), "Logs", "Test", "*.xcresult"))
        for name, root in repos_cache:
            if workspace.startswith(root + os.sep):
                found.setdefault(root, []).extend(results)
    for name, root in repos_cache:
        device = os.path.join(DEVICE_QA_RESULTS, re.sub(r"\W", "_", name) + ".xcresult")
        if os.path.exists(device):
            found.setdefault(root, []).append(device)
    return {root: sorted(paths, key=os.path.getmtime, reverse=True) for root, paths in found.items()}


def coverage(xcresult):
    try:
        out = subprocess.run(["xcrun", "xccov", "view", "--report", "--json", xcresult],
                             capture_output=True, text=True, timeout=120).stdout
        report = json.loads(out)
    except Exception:
        return None
    covered = executable = 0
    for target in report.get("targets", []):
        if target.get("name", "").endswith((".app", ".appex")):
            covered += target.get("coveredLines", 0)
            executable += target.get("executableLines", 0)
    return (covered, executable) if executable else None


repos_cache = list(repos())


def main():
    results = xcresults_by_repo()
    apps = []
    for name, root in repos_cache:
        ids = bundle_ids(root)
        if not ids:
            continue
        tests, files, sources = static_counts(root)
        app = {"folder": name, "bundleIDs": ids, "testFunctions": tests, "testFiles": files, "sourceFiles": sources}
        for xcresult in results.get(root, []):
            lines = coverage(xcresult)
            if lines:
                app.update(coveredLines=lines[0], executableLines=lines[1], measuredAt=iso(os.path.getmtime(xcresult)))
                break
        apps.append(app)
        kind = f"{app['coveredLines'] / app['executableLines']:.0%}" if "coveredLines" in app else f"정적 · 테스트 {tests}개"
        print(f"{name}: {kind}", flush=True)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    with open(OUT, "w", encoding="utf-8") as fh:
        json.dump({"generatedAt": now, "apps": apps}, fh, ensure_ascii=False, indent=1)
    print(f"→ {OUT} ({len(apps)}개 앱)")


if __name__ == "__main__":
    main()
