//
//  VoiceDigest.swift
//  FeedbackHubViewer
//
//  한 문장 의견(LeeoKit `LeeoVoice`, type `voice.*`)을 한 줄씩 읽지 않고 앱마다 모아 센다.
//
//   · 꼭 필요한 사람의 몫 — 쓸모 질문에서 "없으면 안 돼요" 를 고른 비율(Sean Ellis 40% 기준).
//     응답이 적으면 "아직 모름". 잠재력 보드와 앱 브리핑이 같은 값을 본다.
//   · 질문마다 묶음 — 비슷한 말끼리 묶어 몇 번 나왔는지. 두 번 넘게 나온 아쉬움이 고칠 것,
//     가장 많이 나온 바람이 다음에 만들 것.
//   · 사정 — 문장 옆에 설치 며칠째 · 유료인지 · 버전. LeeoKit 3.51.0 부터 `설치:` · `유료:` 줄이
//     함께 온다. 그 전 버전에서 온 것은 버전만 있다.
//

import Foundation

extension Feedback {
    /// 보낼 때 설치한 지 며칠째였나(`설치: N일`). LeeoKit 3.51.0 전이면 nil.
    var installDays: Int? {
        for line in attachedInfoLines where line.hasPrefix("설치:") {
            let digits = line.dropFirst("설치:".count).filter(\.isNumber)
            if let n = Int(digits) { return n }
        }
        return nil
    }

    /// 보낼 때 유료였나(`유료: 예/아니오`). 결제가 없는 앱이거나 옛 버전이면 nil.
    var isPaidUser: Bool? {
        for line in attachedInfoLines where line.hasPrefix("유료:") {
            let value = line.dropFirst("유료:".count).trimmingCharacters(in: .whitespaces)
            if value == "예" { return true }
            if value == "아니오" { return false }
        }
        return nil
    }

    /// 문장 옆에 붙일 사정 — "설치 12일 · 유료 · 1.2.7". 아는 것만.
    var voiceContext: String {
        var parts: [String] = []
        if let days = installDays { parts.append("설치 \(days)일") }
        if let paid = isPaidUser { parts.append(paid ? "유료" : "무료") }
        if let version = appVersion?.trimmingCharacters(in: .whitespaces), !version.isEmpty, version != "-" {
            parts.append(version)
        }
        return parts.joined(separator: " · ")
    }
}

struct VoiceDigest {
    /// 이만큼 답이 모이기 전에는 비율을 말하지 않는다 — 두 명 중 한 명이 50% 로 서지 않게.
    static let minAnswers = 5
    /// 이 몫을 넘으면 꼭 필요로 하는 사람이 있는 앱.
    static let mustHaveBar = 0.4

    enum Question: String, CaseIterable, Identifiable {
        case useful = "voice.useful"
        case unmet = "voice.unmet"
        case wish = "voice.wish"
        var id: String { rawValue }

        var title: String {
            switch self {
            case .useful: return "쓸모 있던 순간"
            case .unmet: return "아쉬웠던 것"
            case .wish: return "바라는 것"
            }
        }

        var systemImage: String {
            switch self {
            case .useful: return "hand.thumbsup.fill"
            case .unmet: return "exclamationmark.bubble.fill"
            case .wish: return "wand.and.stars"
            }
        }

        /// 이 묶음으로 무엇을 하나.
        var use: String {
            switch self {
            case .useful: return "그대로 스토어 부제 · 첫 장 문구 후보로"
            case .unmet: return "두 번 넘게 나오면 고칠 것으로"
            case .wish: return "가장 많이 나온 것을 다음에 만들 것으로"
            }
        }
    }

    /// 비슷한 말 한 묶음. 맨 앞 문장이 대표.
    struct Cluster: Identifiable {
        let items: [Feedback]
        var id: String { items[0].id }
        var count: Int { items.count }
        var lead: Feedback { items[0] }
    }

    let project: String
    /// 한 문장 의견 전부, 새것부터.
    let items: [Feedback]

    init(project: String, feedback: [Feedback]) {
        self.project = project
        self.items = feedback.filter(\.isVoice)
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    var isEmpty: Bool { items.isEmpty }

    // MARK: - 꼭 필요한 사람의 몫

    /// 쓸모 정도를 고른 답(LeeoKit 3.51.0 부터).
    var ratedCount: Int { items.filter { $0.usefulness != nil }.count }
    var mustHaveCount: Int { items.filter { $0.usefulness == 3 }.count }

    /// "없으면 안 돼요" 의 몫. 답이 `minAnswers` 보다 적으면 nil — 아직 모름.
    var mustHaveShare: Double? {
        let rated = ratedCount
        guard rated >= Self.minAnswers else { return nil }
        return Double(mustHaveCount) / Double(rated)
    }

    /// 한 줄 — "없으면 안 돼요 45% (11명 중 5명)" · "아직 모름 (3명 답함)".
    var mustHaveLine: String {
        if let share = mustHaveShare {
            return "없으면 안 돼요 \(Int((share * 100).rounded()))% (\(ratedCount)명 중 \(mustHaveCount)명)"
        }
        return ratedCount == 0 ? "아직 모름 (쓸모 정도를 고른 답 없음)" : "아직 모름 (\(ratedCount)명 답함)"
    }

    // MARK: - 질문마다 묶음

    func items(for question: Question) -> [Feedback] {
        items.filter { $0.feedbackType?.lowercased() == question.rawValue }
    }

    /// 비슷한 말끼리 묶어 많이 나온 것부터. 같으면 최근 것부터.
    func clusters(for question: Question) -> [Cluster] {
        var groups: [(key: Key, items: [Feedback])] = []
        for item in items(for: question) {
            let key = Key(item.text)
            if let index = groups.firstIndex(where: { $0.key.isSimilar(to: key) }) {
                groups[index].items.append(item)
            } else {
                groups.append((key, [item]))
            }
        }
        return groups.map { Cluster(items: $0.items) }
            .sorted { $0.count != $1.count ? $0.count > $1.count
                : ($0.lead.createdAt ?? .distantPast) > ($1.lead.createdAt ?? .distantPast) }
    }

    /// 문장을 견주는 열쇠 — 말마다 앞 두 글자(한국어는 어미가 바뀌어도 "느려요" · "느려서" 가 같다,
    /// 영어는 앞 다섯 글자). 어느 문장에나 나오는 말("너무" · "있었으면 좋겠어요")은 뺀다.
    struct Key {
        let normalized: String
        let stems: Set<String>

        private static let stopWords: Set<String> = [
            "앱이", "앱을", "앱은", "앱", "너무", "정말", "진짜", "그냥", "좀", "있었", "있으", "있어", "좋겠", "좋을",
            "좋아", "해주", "하는", "하고", "해서", "할때", "때", "것", "거", "수", "이게", "이거", "그게", "더", "안", "잘",
            "많이", "같아", "같은", "기능", "있는", "없는",
            "the", "and", "app", "it", "is", "to", "a", "i", "would", "be", "more", "please", "could", "like",
        ]

        init(_ text: String) {
            let letters = text.lowercased().unicodeScalars
                .filter { CharacterSet.alphanumerics.contains($0) || $0 == " " }
            let words = String(String.UnicodeScalarView(letters)).split(separator: " ").map(String.init)
            normalized = words.joined(separator: " ")
            var stems = Set<String>()
            for word in words where !Self.stopWords.contains(word) {
                let latin = word.unicodeScalars.allSatisfy(\.isASCII)
                let stem = latin ? String(word.prefix(5)) : String(word.prefix(2))
                guard latin || stem.count >= 2, !Self.stopWords.contains(stem) else { continue }
                stems.insert(stem)
            }
            self.stems = stems
        }

        /// 같은 문장이거나, 겹치는 말이 많은 쪽 말 수의 절반 이상이면 같은 말로 본다.
        func isSimilar(to other: Key) -> Bool {
            if !normalized.isEmpty, normalized == other.normalized { return true }
            guard !stems.isEmpty, !other.stems.isEmpty else { return false }
            let shared = stems.intersection(other.stems).count
            return Double(shared) / Double(max(stems.count, other.stems.count)) >= 0.5
        }
    }
}
