//
//  KoreanTranslationViews.swift
//  FeedbackHubViewer
//
//  리뷰와 피드백을 한국어로 보여 주는 뷰 셋(`KoreanTranslator` 가 옮긴다).
//
//   - `KoreanText` — 글 한 덩어리. 옮긴 글이 있으면 그것, 없으면 원문. 화면에
//     오르는 순간 번역을 부탁해 두므로, 원문으로 떴다가 한국어로 바뀐다.
//   - `TranslationFooter` — 그 아래 한 줄. 옮긴 글을 보고 있으면 "원문 보기",
//     아직 옮기지 못한 글이면 "한국어로 번역".
//   - `koreanTranslationHost()` — 루트에 한 번. 번역 세션은 뷰에 붙어서만 얻을 수
//     있어, 줄 선 일감을 여기서 돌린다.
//
//  iOS 18 / macOS 15 부터 저절로 옮긴다. iOS 17.4 / macOS 14.4 는 글을 돌려받을
//  길이 없어 원문 그대로 두고 시스템 번역 창을 여는 단추만 둔다.
//

import SwiftUI
import Translation

// MARK: - 글

/// 한국어로 옮긴 글을 먼저 보여 주는 `Text`. 글꼴 · 줄 수 · 색은 밖에서 붙인다.
struct KoreanText: View {
    let text: String
    @ObservedObject private var translator = KoreanTranslator.shared

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(translator.shown(text))
            .task(id: text) { translator.want(text) }
    }
}

// MARK: - 원문 보기

/// 옮긴 글 아래 한 줄: 무엇에서 옮겼는지와 "원문 보기". 리뷰는 제목과 본문이 따로
/// 옮겨지므로 여러 덩어리를 받는다 — 원문은 그 순서대로 한 상자에 편다.
struct TranslationFooter: View {
    let texts: [String]
    @ObservedObject private var translator = KoreanTranslator.shared
    @State private var showsOriginal = false

    init(_ texts: [String?]) {
        self.texts = texts.compactMap { $0 }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var translated: [String] { texts.filter { translator.korean(for: $0) != nil } }
    /// 옮길 만한데 아직 한국어가 없는 덩어리.
    private var untranslated: [String] {
        texts.filter { translator.korean(for: $0) == nil && KoreanTranslator.isWorthTranslating($0) }
    }

    var body: some View {
        let translated = translated
        let untranslated = untranslated
        if !translated.isEmpty || !untranslated.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if !translated.isEmpty {
                    HStack(spacing: 10) {
                        Label(sourceLabel(translated), systemImage: "globe")
                            .foregroundStyle(.secondary)
                        Button(showsOriginal ? "원문 숨기기" : "원문 보기") {
                            withAnimation(.easeOut(duration: 0.15)) { showsOriginal.toggle() }
                        }
                        .buttonStyle(.borderless)
                    }
                    if showsOriginal {
                        originalBox(translated)
                    }
                }
                if !untranslated.isEmpty {
                    pending(untranslated)
                }
            }
            .font(.body)
            // 한 뷰가 고른 글마다 다시 쓰인다 — 앞 글의 펼침이 따라오지 않게.
            .onChange(of: texts) { _, _ in showsOriginal = false }
        }
    }

    private func sourceLabel(_ translated: [String]) -> String {
        let source = translated.compactMap { translator.korean(for: $0)?.source }.first
        return KoreanTranslator.languageLabel(from: source) + " 자동 번역"
    }

    private func originalBox(_ originals: [String]) -> some View {
        let joined = originals.joined(separator: "\n\n")
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("원문")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 12)
                CopyButton(text: joined, title: "원문 복사", isCompact: true)
            }
            Text(joined)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    /// 아직 한국어가 없는 글: 도는 중이면 그렇게 말하고, 아니면 단추.
    @ViewBuilder
    private func pending(_ untranslated: [String]) -> some View {
        if untranslated.contains(where: translator.isWorking) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("번역 중…").foregroundStyle(.secondary)
            }
        } else if #available(iOS 18.0, macOS 15.0, *) {
            if let failure = untranslated.compactMap(translator.failure(for:)).first {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }
            Button {
                translator.translateNow(untranslated)
            } label: {
                Label("한국어로 번역", systemImage: "globe")
            }
            .buttonStyle(.borderless)
        } else if #available(iOS 17.4, macOS 14.4, *) {
            SystemTranslationButton(text: untranslated.joined(separator: "\n\n"))
        }
    }
}

/// iOS 17.4 / macOS 14.4: 같은 엔진을 시스템의 번역 창으로. 글을 돌려받지 못해
/// 화면의 글은 원문 그대로 남는다.
@available(iOS 17.4, macOS 14.4, *)
private struct SystemTranslationButton: View {
    let text: String
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Label("한국어로 번역", systemImage: "globe")
        }
        .buttonStyle(.borderless)
        .translationPresentation(isPresented: $isPresented, text: text)
    }
}

// MARK: - 세션을 돌리는 자리

extension View {
    /// 루트에 한 번 붙인다. 줄 선 번역 일감을 하나씩 꺼내 돌린다.
    @ViewBuilder
    func koreanTranslationHost() -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            modifier(KoreanTranslationHost())
        } else {
            self
        }
    }
}

@available(iOS 18.0, macOS 15.0, *)
private struct KoreanTranslationHost: ViewModifier {
    @ObservedObject private var translator = KoreanTranslator.shared
    /// 이 값을 바꾸거나 무효로 하면 `translationTask` 가 새 세션으로 다시 돈다.
    @State private var configuration: TranslationSession.Configuration?

    func body(content: Content) -> some View {
        content
            .translationTask(configuration) { session in
                guard let job = translator.current else { return }
                await translator.run(job, with: session)
            }
            .onChange(of: translator.current?.id, initial: true) { _, id in
                guard id != nil, let job = translator.current else { return }
                let source = job.source.map(Locale.Language.init(identifier:))
                let next = TranslationSession.Configuration(source: source,
                                                            target: Locale.Language(identifier: "ko"))
                if let configuration, configuration.source == next.source, configuration.target == next.target {
                    // 같은 언어의 다음 일감 — 같은 값으로는 다시 돌지 않으므로 무효로 한다.
                    self.configuration?.invalidate()
                } else {
                    configuration = next
                }
            }
    }
}
