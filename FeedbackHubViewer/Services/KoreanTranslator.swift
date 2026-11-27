//
//  KoreanTranslator.swift
//  FeedbackHubViewer
//
//  리뷰와 피드백을 한국어로 — 묻지 않아도. 글은 쓴 사람의 말로 오고 읽는 사람은
//  한국어로 읽으니, 화면에 오르는 글을 여기서 미리 옮겨 두고 뷰는 옮긴 글을 먼저
//  보여 준다(`KoreanText`). 원문은 "원문 보기"로 편다(`TranslationFooter`).
//
//  옮기는 것은 애플의 Translation 프레임워크뿐이다: 키도 계정도 우리 서버도 없이
//  기기 안에서 돈다. 다만 그 세션은 뷰에 붙어서만 얻을 수 있어(`translationTask`)
//  일감을 여기 줄 세우고, 루트에 붙은 한 뷰가 하나씩 꺼내 돌린다
//  (`koreanTranslationHost()`).
//
//  저절로 옮기는 것은 **이미 내려받은 언어**뿐이다. 내려받지 않은 언어를 저절로
//  옮기려 들면 목록을 넘길 때마다 시스템의 내려받기 창이 뜬다 — 그 언어는 단추를
//  눌렀을 때 한 번 묻고, 내려받은 뒤로는 그 언어의 글도 저절로 옮긴다.
//
//  옮긴 글은 캐시 폴더의 파일 하나에 남겨, 다음 실행에는 바로 한국어로 뜬다.
//

import Foundation
import NaturalLanguage
import Translation

@MainActor
final class KoreanTranslator: ObservableObject {
    static let shared = KoreanTranslator()

    /// 옮긴 글 하나.
    struct Entry: Codable, Equatable {
        var text: String
        /// 원문의 언어("en"). 프레임워크가 알려 준 것, 없으면 우리가 짐작한 것.
        var source: String?
        var at: Date
    }

    /// 한 번에 돌리는 일감 — 세션 하나가 원문 언어 하나를 맡는다.
    struct Job: Identifiable, Equatable {
        let id = UUID()
        /// `nil` 이면 프레임워크가 글에서 알아낸다(손으로 누른 것만).
        let source: String?
        var texts: [String]
    }

    /// 원문(다듬은 것) → 옮긴 글.
    @Published private(set) var entries: [String: Entry] = [:]
    /// 줄에 섰거나 도는 중인 원문.
    @Published private(set) var working: Set<String> = []
    /// 옮기지 못한 원문 → 까닭.
    @Published private(set) var failures: [String: String] = [:]
    /// 지금 도는 일감. 바뀌면 호스트 뷰가 세션을 새로 연다.
    @Published private(set) var current: Job?

    private var queue: [Job] = []
    /// 이번 실행에서 한 번 살펴본 원문 — 줄마다 다시 묻지 않게.
    private var seen: Set<String> = []
    /// 언어를 내려받지 않아 미뤄 둔 원문. 그 언어가 생기면 줄에 세운다.
    private var waiting: [String: Set<String>] = [:]
    /// 언어 → 저절로 옮길 수 있는가(내려받았는가).
    private var installed: [String: Bool] = [:]
    private var saveTask: Task<Void, Never>?

    private static let batchSize = 30
    private static let keepLimit = 5000

    private init() {
        load()
    }

    // MARK: - 읽기

    static func key(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 한국어로 옮긴 글. 아직 없거나 옮길 필요가 없으면 `nil`.
    func korean(for text: String) -> Entry? {
        entries[Self.key(text)]
    }

    /// 화면에 올릴 글 — 옮긴 것이 있으면 그것, 없으면 원문.
    func shown(_ text: String) -> String {
        korean(for: text)?.text ?? text
    }

    func isWorking(_ text: String) -> Bool {
        working.contains(Self.key(text))
    }

    func failure(for text: String) -> String? {
        failures[Self.key(text)]
    }

    /// "영어 → 한국어".
    static func languageLabel(from source: String?) -> String {
        guard let source,
              let code = Locale.Language(identifier: source).languageCode?.identifier,
              let name = AppFormat.locale.localizedString(forLanguageCode: code) else {
            return "한국어 번역"
        }
        return "\(name) → 한국어"
    }

    // MARK: - 언어 알아보기

    /// 옮길 만한 글인가. 한국어 글은 아니다 — 다만 **확신할 때만**: 몇 낱말짜리 글에서
    /// 판별기는 짐작을 하고, 잘못 짐작해 번역을 감추는 쪽이 더 나쁘다.
    static func isWorthTranslating(_ text: String) -> Bool {
        let trimmed = key(text)
        guard trimmed.count >= 2 else { return false }
        // 글자가 하나도 없으면(별 · 이모지 · 숫자뿐) 옮길 것이 없다.
        guard trimmed.unicodeScalars.contains(where: CharacterSet.letters.contains) else { return false }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        guard let language = recognizer.dominantLanguage, language == .korean else { return true }
        return (recognizer.languageHypotheses(withMaximum: 1)[language] ?? 0) < 0.7
    }

    /// 저절로 옮길 때 세션에 넘길 원문 언어. 확신이 서지 않으면 `nil` — 잘못 짚은
    /// 언어로 옮긴 글은 엉뚱하고, 그런 글은 단추로 남겨 프레임워크가 알아내게 한다.
    private static func confidentSource(of text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(key(text))
        guard let language = recognizer.dominantLanguage, language != .korean, language != .undetermined,
              (recognizer.languageHypotheses(withMaximum: 1)[language] ?? 0) >= 0.5 else { return nil }
        return language.rawValue
    }

    // MARK: - 부탁하기

    /// 이 글이 화면에 올랐다 — 옮길 수 있으면 옮겨 둔다. 줄마다 불러도 된다.
    func want(_ text: String) {
        guard #available(iOS 18.0, macOS 15.0, *) else { return }
        let key = Self.key(text)
        guard !seen.contains(key), entries[key] == nil else { return }
        seen.insert(key)
        guard Self.isWorthTranslating(key), let source = Self.confidentSource(of: key) else { return }

        Task {
            if await isInstalled(source) {
                enqueue([key], source: source)
            } else {
                waiting[source, default: []].insert(key)
            }
        }
    }

    /// "한국어로 번역" 단추. 언어를 내려받아야 하면 시스템이 여기서 묻는다.
    func translateNow(_ texts: [String]) {
        guard #available(iOS 18.0, macOS 15.0, *) else { return }
        for text in texts {
            let key = Self.key(text)
            guard Self.isWorthTranslating(key), entries[key] == nil, !working.contains(key) else { continue }
            seen.insert(key)
            failures[key] = nil
            // 손으로 누른 것은 줄 맨 앞에, 그리고 언어는 프레임워크가 알아낸다.
            let job = Job(source: Self.confidentSource(of: key), texts: [key])
            working.insert(key)
            queue.insert(job, at: 0)
        }
        advance()
    }

    @available(iOS 18.0, macOS 15.0, *)
    private func isInstalled(_ source: String) async -> Bool {
        if let known = installed[source] { return known }
        let status = await LanguageAvailability().status(from: Locale.Language(identifier: source),
                                                         to: Locale.Language(identifier: "ko"))
        let isInstalled = status == .installed
        installed[source] = isInstalled
        return isInstalled
    }

    private func enqueue(_ keys: [String], source: String) {
        for key in keys where entries[key] == nil && !working.contains(key) {
            working.insert(key)
            // 같은 언어의 덜 찬 일감에 얹는다 — 세션을 글마다 새로 열지 않게.
            if let index = queue.lastIndex(where: { $0.source == source && $0.texts.count < Self.batchSize }) {
                queue[index].texts.append(key)
            } else {
                queue.append(Job(source: source, texts: [key]))
            }
        }
        advance()
    }

    private func advance() {
        guard current == nil, !queue.isEmpty else { return }
        current = queue.removeFirst()
    }

    // MARK: - 돌리기

    /// 호스트 뷰가 세션을 얻으면 부른다. 지금 일감 하나를 옮기고 다음으로 넘긴다.
    @available(iOS 18.0, macOS 15.0, *)
    func run(_ job: Job, with session: TranslationSession) async {
        guard current?.id == job.id else { return }
        do {
            let requests = job.texts.map { TranslationSession.Request(sourceText: $0, clientIdentifier: $0) }
            let responses = try await session.translations(from: requests)
            for response in responses {
                guard let key = response.clientIdentifier else { continue }
                let source = response.sourceLanguage.minimalIdentifier
                entries[key] = Entry(text: response.targetText, source: source, at: Date())
                failures[key] = nil
            }
            scheduleSave()
            // 이 언어는 이제 기기에 있다 — 미뤄 둔 같은 언어의 글을 줄에 세운다.
            if let source = job.source ?? responses.first?.sourceLanguage.minimalIdentifier {
                languageBecameAvailable(source)
            }
        } catch is CancellationError {
            // 세션이 닫혔다. 잘못된 것은 없고, 다음에 화면에 오르면 다시 묻는다.
            seen.subtract(job.texts)
        } catch {
            let message = Self.message(for: error)
            for key in job.texts { failures[key] = message }
        }
        working.subtract(job.texts)
        guard current?.id == job.id else { return }
        current = nil
        advance()
    }

    private func languageBecameAvailable(_ source: String) {
        let code = Locale.Language(identifier: source).languageCode?.identifier ?? source
        for (language, keys) in waiting {
            let waitingCode = Locale.Language(identifier: language).languageCode?.identifier ?? language
            guard language == source || waitingCode == code else { continue }
            installed[language] = true
            waiting[language] = nil
            enqueue(Array(keys), source: language)
        }
        installed[source] = true
    }

    private static func message(for error: Error) -> String {
        if #available(iOS 18.0, macOS 15.0, *) {
            switch error {
            case TranslationError.unsupportedLanguagePairing,
                 TranslationError.unsupportedSourceLanguage:
                return "이 언어는 한국어로 번역할 수 없습니다."
            case TranslationError.unableToIdentifyLanguage:
                return "어떤 언어인지 알아내지 못했습니다."
            default:
                break
            }
        }
        return "번역하지 못했습니다: \(error.localizedDescription)"
    }

    // MARK: - 파일

    private static var fileURL: URL {
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return folder.appendingPathComponent("KoreanTranslations.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let saved = try? JSONDecoder().decode([String: Entry].self, from: data) else { return }
        entries = saved
    }

    /// 한 묶음이 끝날 때마다 쓰지 않고, 잠잠해지면 한 번.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            var snapshot = self.entries
            if snapshot.count > Self.keepLimit {
                // 오래된 것부터 버린다 — 지워져도 다시 옮기면 그만이다.
                let kept = snapshot.sorted { $0.value.at > $1.value.at }.prefix(Self.keepLimit)
                snapshot = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
            }
            let url = Self.fileURL
            Task.detached(priority: .utility) {
                guard let data = try? JSONEncoder().encode(snapshot) else { return }
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
