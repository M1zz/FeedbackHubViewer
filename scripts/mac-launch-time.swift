// 맥 앱을 새로 켜서 첫 창이 화면에 뜰 때까지 걸린 밀리초를 찍고 앱을 끈다.
// Instruments App Launch 는 맥에서 "첫 화면" 단계를 남기지 않아 이것으로 잰다(device-perf.py 가 부른다).
//
//     mac-launch-time <앱 경로>      →  표준 출력에 밀리초 한 줄, 못 재면 종료 코드 1
import AppKit

guard CommandLine.arguments.count > 1 else { exit(2) }
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let config = NSWorkspace.OpenConfiguration()
config.createsNewApplicationInstance = true
// 앞으로 띄우지 않으면 SwiftUI 앱은 첫 창을 열지 않는다 — 사용자가 처음 켤 때처럼 앞으로 띄운다.
config.activates = true

let start = DispatchTime.now()
var launched: NSRunningApplication?
let opened = DispatchSemaphore(value: 0)
NSWorkspace.shared.openApplication(at: url, configuration: config) { app, _ in
    launched = app
    opened.signal()
}
guard opened.wait(timeout: .now() + 30) == .success, let app = launched else { exit(1) }

func hasWindow(_ pid: pid_t) -> Bool {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return list.contains { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }
}

let deadline = Date().addingTimeInterval(30)
while !hasWindow(app.processIdentifier) {
    if Date() > deadline || app.isTerminated { app.forceTerminate(); exit(1) }
    usleep(2_000)
}
let ms = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
print(Int(ms.rounded()))
app.terminate()
usleep(500_000)
if !app.isTerminated { app.forceTerminate() }
