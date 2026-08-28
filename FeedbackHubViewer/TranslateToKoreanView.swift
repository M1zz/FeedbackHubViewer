//
//  TranslateToKoreanView.swift
//  FeedbackHubViewer
//
//  Turns one piece of feedback into Korean, using Apple's own Translation
//  framework and nothing else: no API key, no account, no server of ours. The
//  translation runs on device, and the first time a language is needed the
//  system itself offers to download it — there is nothing to configure here or
//  in the project.
//

import SwiftUI
import Translation
import NaturalLanguage

/// A "한국어로 번역" control for a block of feedback text.
///
/// Feedback arrives in whatever language the person who wrote it speaks, and it
/// has to be read in Korean. Two generations of the framework can do that, and
/// which one is present decides how the result is shown:
///
///  - iOS 18 / macOS 15 have `TranslationSession`, which hands the string back
///    so it can sit inline under the original — both languages on screen at
///    once, which is what you want when judging a bug report.
///  - iOS 17.4 / macOS 14.4 only have `translationPresentation`, the system
///    popover. Same engine, less control over where the result lands.
///
/// Anything older gets no button at all — which is why this is a view rather
/// than a modifier: the availability check has to be able to render nothing.
struct TranslateToKoreanView: View {
    let text: String

    var body: some View {
        if Self.isWorthTranslating(text) {
            if #available(iOS 18.0, macOS 15.0, *) {
                InlineTranslation(text: text)
            } else if #available(iOS 17.4, macOS 14.4, *) {
                PopoverTranslation(text: text)
            }
        }
    }

    /// Whether a translate button belongs on this text at all. Korean feedback
    /// does not need one, and `NaturalLanguage` answers that on device too.
    ///
    /// Only a *confident* "this is Korean" hides the button: on a few words the
    /// recogniser is guessing, and a wrong guess that hides the button is worse
    /// than a button nobody needed.
    static func isWorthTranslating(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return false }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        guard let language = recognizer.dominantLanguage, language == .korean else { return true }
        return (recognizer.languageHypotheses(withMaximum: 1)[language] ?? 0) < 0.7
    }

    /// "영어 → 한국어", in the reader's own language.
    static func languageLabel(from source: Locale.Language?) -> String {
        guard let code = source?.languageCode?.identifier,
              let name = AppFormat.locale.localizedString(forLanguageCode: code) else {
            return "한국어 번역"
        }
        return "\(name) → 한국어"
    }
}

// MARK: - Inline (iOS 18 / macOS 15+)

/// The original stays put and the translation appears under it. State is per
/// feedback: selecting another record clears it rather than leaving the
/// previous translation under the new text.
@available(iOS 18.0, macOS 15.0, *)
private struct InlineTranslation: View {
    let text: String

    /// Setting this — or invalidating it — is what runs `translationTask`.
    /// `nil` means "not asked for yet", which is also the collapsed state.
    @State private var configuration: TranslationSession.Configuration?
    @State private var result: Translated?
    @State private var errorText: String?
    @State private var isTranslating = false

    private struct Translated {
        var text: String
        var sourceLanguage: Locale.Language?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let result {
                translationBox(result)
            }
            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            controls
        }
        .translationTask(configuration) { session in
            await translate(with: session)
        }
        // The detail view reuses this view for whichever feedback is selected,
        // so the previous record's translation has to go with it.
        .onChange(of: text) { _, _ in
            configuration = nil
            result = nil
            errorText = nil
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                requestTranslation()
            } label: {
                Label(result == nil ? "한국어로 번역" : "다시 번역", systemImage: "globe")
            }
            .disabled(isTranslating)

            if isTranslating {
                ProgressView()
                    .controlSize(.small)
                Text("번역 중…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if result != nil {
                Button("번역 숨기기") {
                    result = nil
                    configuration = nil
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func translationBox(_ result: Translated) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(TranslateToKoreanView.languageLabel(from: result.sourceLanguage))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(result.text)
                .font(.title3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    private func requestTranslation() {
        errorText = nil
        // The source language is left unset on purpose: identifying it is the
        // whole point, and the framework does it from the text itself.
        let target = Locale.Language(identifier: "ko")
        if configuration == nil {
            configuration = TranslationSession.Configuration(source: nil, target: target)
        } else {
            // "다시 번역" asks for the same configuration as last time, and an
            // equal value would not restart the task — invalidating does.
            configuration?.invalidate()
        }
    }

    @MainActor
    private func translate(with session: TranslationSession) async {
        isTranslating = true
        defer { isTranslating = false }
        do {
            let response = try await session.translate(text)
            result = Translated(text: response.targetText, sourceLanguage: response.sourceLanguage)
            errorText = nil
        } catch is CancellationError {
            // Selecting another feedback mid-translation. Nothing went wrong.
        } catch {
            result = nil
            errorText = Self.message(for: error)
        }
    }

    /// The framework's own errors are precise but English; the two a reader is
    /// actually likely to hit get said plainly.
    private static func message(for error: Error) -> String {
        switch error {
        case TranslationError.unsupportedLanguagePairing,
             TranslationError.unsupportedSourceLanguage:
            return "이 언어는 한국어로 번역할 수 없습니다."
        case TranslationError.unableToIdentifyLanguage:
            return "어떤 언어인지 알아내지 못했습니다."
        default:
            return "번역하지 못했습니다: \(error.localizedDescription)"
        }
    }
}

// MARK: - System popover (iOS 17.4 / macOS 14.4+)

/// The fallback: the same on-device engine, shown in the system's own
/// translation popover. It translates into the device's preferred language
/// rather than one this app picks, which on a Korean system is the same thing.
@available(iOS 17.4, macOS 14.4, *)
private struct PopoverTranslation: View {
    let text: String
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Label("한국어로 번역", systemImage: "globe")
        }
        .translationPresentation(isPresented: $isPresented, text: text)
    }
}
