//
//  CrashAnalysis.swift
//  FeedbackHubViewer
//
//  진단 한 건을 **읽을 수 있는 것**으로 바꾸는 층. 콜스택을 프레임으로 가르고, 어느
//  줄이 내 코드인지 고르고, 같은 사고끼리 묶을 지문을 만든다.
//
//  왜 필요한가: 크래시는 한 건씩 보면 아무것도 알려주지 않는다. "이 사고가 몇 번,
//  어느 버전부터, 몇 종류 기기에서" 가 있어야 고칠 순서가 정해진다. 그게 이슈다.
//
//  ⚠️ 심볼이 없다. 오프셋은 함수 이름이 아니고, 빌드가 바뀌면 값도 바뀐다.
//     그래서 지문은 **오프셋이 아니라 바이너리 이름의 흐름**으로 만든다. 덕분에 이슈가
//     버전을 가로질러 묶이지만, 같은 바이너리 안의 서로 다른 자리는 한 이슈로 합쳐진다.
//     그 안쪽을 가르는 것이 `variants` 다. 함수 이름까지 보려면 dSYM 이 필요하다
//     (README 의 "심볼로 되돌리기" 절).
//

import Foundation

extension CrashReport {

    // MARK: - 시각 · 버전

    /// 크래시가 **난** 시각. 옛 레코드는 그 값이 없어 도착 시각으로 대신한다.
    /// (MetricKit 배달이 하루까지 늦으므로 둘은 같지 않다)
    var happenedAt: Date? { occurredAt ?? receivedAt }

    /// 시각이 실제 발생 시각인가, 도착 시각을 대신 쓴 것인가.
    var hasExactTime: Bool { occurredAt != nil }

    /// 화면에 쓸 버전 이름표. 빌드 번호가 있으면 함께 보인다.
    var versionLabel: String {
        guard let buildNumber, !buildNumber.isEmpty, buildNumber != "-" else { return appVersion }
        return "\(appVersion) (\(buildNumber))"
    }

    /// 신호·예외를 한 줄로. 없으면 nil.
    var signalLabel: String? {
        var parts: [String] = []
        if let signal, !signal.isEmpty { parts.append("signal \(Self.signalName(signal))") }
        if let exceptionType, !exceptionType.isEmpty { parts.append("exception \(exceptionType)") }
        if let exceptionCode, !exceptionCode.isEmpty, exceptionCode != "0" { parts.append("code \(exceptionCode)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// 숫자만 오는 신호에 이름을 붙인다. 모르면 숫자 그대로.
    static func signalName(_ raw: String) -> String {
        switch raw {
        case "4":  return "4 SIGILL"
        case "5":  return "5 SIGTRAP"
        case "6":  return "6 SIGABRT"
        case "8":  return "8 SIGFPE"
        case "9":  return "9 SIGKILL"
        case "10": return "10 SIGBUS"
        case "11": return "11 SIGSEGV"
        default:   return raw
        }
    }

    // MARK: - 원인 갈래

    /// 왜 죽었나를 굵게 가른다. 이 앱에서 압도적으로 많은 것이 워치독이라
    /// 그 안쪽을 한 번 더 나눈다. 어느 쪽이냐에 따라 볼 곳이 완전히 다르기 때문이다.
    enum Cause: String, CaseIterable {
        /// 백그라운드로 갈 때 메인 스레드가 안 놓여서 iOS 가 죽였다.
        case watchdogTerminate
        /// 화면을 제때 못 그려서 죽었다. 대개 런치나 첫 화면이다.
        case watchdogScene
        /// 그 밖의 0x8BADF00D.
        case watchdogOther
        /// 메모리 부족으로 iOS 가 회수했다.
        case memory
        /// 신호로 죽었다(SIGSEGV·SIGABRT 등). 진짜 크래시다.
        case signal
        /// 멈춤 진단.
        case hang
        /// 디스크 쓰기 예외.
        case diskWrite
        /// 가르지 못했다.
        case unknown

        var label: String {
            switch self {
            case .watchdogTerminate: return "워치독: 종료 지연"
            case .watchdogScene:     return "워치독: 화면 갱신 지연"
            case .watchdogOther:     return "워치독: 기타"
            case .memory:            return "메모리 부족"
            case .signal:            return "신호"
            case .hang:              return "멈춤"
            case .diskWrite:         return "디스크 쓰기"
            case .unknown:           return "분류 안 됨"
            }
        }

        /// 무엇을 들여다봐야 하는지 한 줄로. 크래시 목록에서 가장 아쉬운 것이
        /// "그래서 뭘 보라는 거냐" 라서 화면에 같이 띄운다.
        var hint: String {
            switch self {
            case .watchdogTerminate:
                return "앱이 백그라운드로 갈 때 메인 스레드가 막혀 있었습니다. 저장·동기화·정리 작업을 봅니다."
            case .watchdogScene:
                return "화면을 제때 못 그렸습니다. 런치 경로와 첫 화면의 무거운 작업을 봅니다."
            case .watchdogOther:
                return "메인 스레드가 오래 막혔습니다. 콜스택의 내 코드 프레임부터 봅니다."
            case .memory:
                return "메모리를 너무 썼습니다. 이미지·대량 로드를 봅니다."
            case .signal:
                return "강제 언래핑·인덱스 초과·의도적 중단일 수 있습니다. 콜스택 0번을 봅니다."
            case .hang:
                return "죽지는 않았지만 멈췄습니다. 사용자는 이것도 고장으로 느낍니다."
            case .diskWrite:
                return "디스크에 너무 많이 썼습니다. 반복 저장을 봅니다."
            case .unknown:
                return "종료 사유가 안 실렸습니다. 콜스택으로 판단합니다."
            }
        }

        var isWatchdog: Bool {
            self == .watchdogTerminate || self == .watchdogScene || self == .watchdogOther
        }
    }

    var cause: Cause {
        switch kind {
        case "hang":       return .hang
        case "disk_write": return .diskWrite
        default:           break
        }
        if detail.contains("0x8BADF00D") {
            if detail.contains("scene-update") { return .watchdogScene }
            if detail.contains("Failed to terminate") { return .watchdogTerminate }
            return .watchdogOther
        }
        if detail.contains("0x8BADF00D") == false,
           detail.localizedCaseInsensitiveContains("jetsam") || detail.contains("0xdead10cc") {
            return .memory
        }
        if signal != nil || detail.contains("SIGNAL") { return .signal }
        return .unknown
    }

    // MARK: - 콜스택

    /// 콜스택 한 줄. 0번이 죽은 자리다.
    struct Frame: Identifiable, Hashable {
        let id: Int
        /// 바이너리 이름. 옛 레코드에는 없어 "?" 로 온다.
        let binary: String
        /// 텍스트 세그먼트 오프셋. 심볼이 없으니 이게 자리를 가리키는 전부다.
        let offset: String
        /// 애플 프레임워크·런타임인가. 아니면 내 코드이거나 붙인 라이브러리다.
        let isSystem: Bool
    }

    /// 애플이 주는 바이너리인지 가린다.
    ///
    /// 앱 바이너리 이름을 미리 알 수 없어(`appId` 는 번들 ID 라 이름과 다르다)
    /// **시스템 쪽을 알아보고 나머지를 내 코드로 본다.** 틀리는 쪽이 안전한 방향이다.
    /// 라이브러리를 내 코드로 잘못 봐도 "여기부터 보라"는 안내가 어긋날 뿐이지만,
    /// 내 코드를 시스템으로 보면 범인 줄이 아예 안 보인다.
    static func isSystemBinary(_ name: String) -> Bool {
        if name == "?" { return false }
        if name.hasPrefix("lib") || name.hasPrefix("dyld") { return true }
        let known: Set<String> = [
            "UIKitCore", "SwiftUI", "Foundation", "CoreFoundation", "CoreGraphics",
            "QuartzCore", "CoreData", "CloudKit", "CoreServices", "GraphicsServices",
            "AttributeGraph", "UIKit", "AppKit", "CoreAutoLayout", "CoreText",
            "CoreImage", "ImageIO", "Combine", "Dispatch", "os", "Security",
            "Network", "CFNetwork", "StoreKit", "MetricKit", "Vision", "Photos",
            "AVFoundation", "CoreMedia", "WebKit", "SwiftUICore", "UIFoundation",
            "BackBoardServices", "FrontBoardServices", "RunningBoardServices",
            "SpringBoardServices", "BaseBoard", "swiftCore", "objc"
        ]
        if known.contains(name) { return true }
        // Swift 런타임·시스템 프레임워크는 접두어로도 잡힌다.
        return name.hasPrefix("Swift") || name.hasPrefix("_") || name.hasPrefix("Core")
    }

    /// 옛 형식(JSON 덩어리)인가. 그건 갈라 볼 수가 없다.
    /// 자세한 사연은 ClipKeyboard 의 docs/postmortem/CRASH_STACK_TRUNCATION.md.
    var isLegacyStack: Bool {
        stack.hasPrefix("{") || stack.hasPrefix("[")
    }

    /// 콜스택을 프레임으로 가른다. 0번이 죽은 자리다.
    var frames: [Frame] {
        guard !isLegacyStack else { return [] }
        var result: [Frame] = []
        for line in stack.split(separator: "\n", omittingEmptySubsequences: true) {
            let text = line.trimmingCharacters(in: .whitespaces)
            // "... 뿌리 쪽 42프레임 생략" 같은 안내 줄은 프레임이 아니다.
            guard !text.hasPrefix("...") else { continue }
            // " 12 ClipKeyboard +820588"
            let parts = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 3, let index = Int(parts[0]) else { continue }
            let offset = parts[parts.count - 1]
            let binary = parts[1..<(parts.count - 1)].joined(separator: " ")
            result.append(Frame(id: index,
                                binary: binary,
                                offset: offset.hasPrefix("+") ? String(offset.dropFirst()) : offset,
                                isSystem: Self.isSystemBinary(binary)))
        }
        return result
    }

    /// 뿌리 쪽이 잘렸다고 알리는 줄이 있으면 그 문장.
    var truncationNote: String? {
        stack.split(separator: "\n").first { $0.hasPrefix("...") }.map(String.init)
    }

    /// **여기부터 보라**는 줄. 죽은 자리에서 가장 가까운 내 코드 프레임이다.
    /// 전부 시스템이면 0번을 준다(그 자체가 단서다).
    var culprit: Frame? {
        let all = frames
        return all.first { !$0.isSystem } ?? all.first
    }

    // MARK: - 지문

    /// 같은 사고끼리 묶는 열쇠.
    ///
    /// 종류 + 원인 + **바이너리 이름의 흐름**으로 만든다. 오프셋을 넣으면 빌드가 바뀔
    /// 때마다 같은 사고가 새 이슈로 갈라져 "언제부터 생겼나"를 물을 수 없다. 심볼이
    /// 없는 동안의 절충이고, 이름만으로는 같은 바이너리의 다른 자리가 한데 묶인다.
    /// 그 안쪽은 `CrashIssue.variants` 가 갈라 보여 준다.
    var fingerprint: String {
        guard !isLegacyStack else { return "legacy|\(kind)" }
        let shape = frames.prefix(6).map(\.binary).joined(separator: ">")
        guard !shape.isEmpty else { return "empty|\(kind)|\(cause.rawValue)" }
        return "\(kind)|\(cause.rawValue)|\(shape)"
    }

    // MARK: - 심볼로 되돌리기

    /// 스택 끝에 붙은 범례. 바이너리 이름 → 그 빌드의 UUID.
    ///
    /// 오프셋을 함수 이름으로 되돌리려면 **정확히 그 빌드의 dSYM** 이어야 한다.
    /// 버전 이름만으로는 못 고른다(같은 5.0.6 이라도 빌드가 여럿이다). UUID 가
    /// 그 하나를 가리키는 열쇠라, 보내는 쪽이 바이너리마다 한 번씩 실어 준다.
    var binaryUUIDs: [String: String] {
        var result: [String: String] = [:]
        for line in stack.split(separator: "\n") {
            guard line.hasPrefix("@ ") else { continue }
            let parts = line.dropFirst(2).split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2 else { continue }
            result[String(parts[0])] = String(parts[1])
        }
        return result
    }

    /// 이 줄을 함수 이름으로 되돌리는 명령. dSYM 을 찾는 한 줄이 앞에 붙는다.
    ///
    /// `atos` 는 **실행 주소**를 받는데, 우리가 가진 건 텍스트 세그먼트 기준
    /// 오프셋이다. 64비트 앱의 세그먼트 시작이 `0x100000000` 이라, 로드 주소를
    /// 그것으로 두고 주소를 `시작 + 오프셋` 으로 준다.
    func symbolicationCommand(for frame: Frame) -> String? {
        guard let offset = Int(frame.offset) else { return nil }
        let base = 0x1_0000_0000
        let address = String(base + offset, radix: 16)
        let binary = frame.binary

        var lines: [String] = []
        if let uuid = binaryUUIDs[binary] {
            // UUID 로 찾아야 정확히 그 빌드의 dSYM 이 나온다.
            lines.append("mdfind \"com_apple_xcode_dsym_uuids == \(uuid)\"")
        } else {
            lines.append("# \(binary) 의 UUID 가 안 실렸습니다. 그 빌드의 dSYM 을 직접 고르세요.")
        }
        lines.append("atos -o <dSYM>/Contents/Resources/DWARF/\(binary) -arch arm64e -l 0x\(String(base, radix: 16)) 0x\(address)")
        return lines.joined(separator: "\n")
    }

    /// 한 이슈 안에서 서로 다른 자리를 가르는 열쇠. 오프셋까지 본다.
    var variantKey: String {
        frames.prefix(4).map { "\($0.binary)+\($0.offset)" }.joined(separator: ">")
    }
}
