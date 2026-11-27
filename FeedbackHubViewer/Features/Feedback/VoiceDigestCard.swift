//
//  VoiceDigestCard.swift
//  FeedbackHubViewer
//
//  앱 하나의 한 문장 의견을 모아 본다(`VoiceDigest`). 앱 브리핑 오른쪽 칸에 선다.
//
//   1. 꼭 필요한 사람의 몫 — "없으면 안 돼요 N%", 40% 를 넘으면 초록.
//   2. 질문마다 비슷한 말끼리 묶어 많이 나온 것부터, 몇 번 나왔는지와 그 사람의 사정
//      (설치 며칠째 · 유료 · 버전)을 문장 옆에.
//   3. 쓸모 답에 별을 달면 "스토어 문구 후보" 로 모인다 — 부제 · 첫 장 문구를 쓸 때 꺼내 본다.
//

import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

struct VoiceDigestCard: View {
    let project: String

    @EnvironmentObject private var store: FeedbackStore
    /// 스토어 문구 후보로 고른 한 문장 id, 줄바꿈으로 잇는다. 이 기기에만 남는다.
    @AppStorage("voice-store-copy") private var storeCopyRaw = ""
    @State private var expanded: Set<VoiceDigest.Question> = []

    private var digest: VoiceDigest { VoiceDigest(project: project, feedback: store.feedback(for: project)) }
    private var storeCopy: Set<String> { Set(storeCopyRaw.split(separator: "\n").map(String.init)) }

    var body: some View {
        let digest = digest
        if !digest.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                mustHave(digest)
                candidates(digest)
                ForEach(VoiceDigest.Question.allCases) { question in
                    let clusters = digest.clusters(for: question)
                    if !clusters.isEmpty { section(question, clusters: clusters) }
                }
            }
        }
    }

    // MARK: - 꼭 필요한 사람의 몫

    private func mustHave(_ digest: VoiceDigest) -> some View {
        let share = digest.mustHaveShare
        let tint: Color = share.map { $0 >= VoiceDigest.mustHaveBar ? .green : .orange } ?? .secondary
        return VStack(alignment: .leading, spacing: 4) {
            Label(digest.mustHaveLine, systemImage: "heart.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
            Text(share == nil
                 ? "쓸모 질문에서 '없으면 안 돼요' 를 고른 몫. \(VoiceDigest.minAnswers)명이 답하면 보입니다(LeeoKit 3.51.0 부터)"
                 : (share! >= VoiceDigest.mustHaveBar
                    ? "40% 를 넘었어요 — 꼭 필요로 하는 사람이 있는 앱입니다"
                    : "40% 아래 — 아직 '있으면 좋은' 앱입니다"))
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 스토어 문구 후보

    @ViewBuilder
    private func candidates(_ digest: VoiceDigest) -> some View {
        let picked = digest.items.filter { storeCopy.contains($0.id) }
        if !picked.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("스토어 문구 후보 \(picked.count)", systemImage: "star.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.yellow)
                    Spacer()
                    Button("모두 복사") { copy(picked.map(\.text).joined(separator: "\n")) }
                        .buttonStyle(.borderless)
                        .font(.body)
                }
                ForEach(picked, id: \.id) { item in
                    Text("“\(item.text)”")
                        .font(.body)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(.yellow.opacity(0.1)))
        }
    }

    // MARK: - 질문마다

    private func section(_ question: VoiceDigest.Question, clusters: [VoiceDigest.Cluster]) -> some View {
        let limit = 3
        let isOpen = expanded.contains(question)
        let shown = isOpen ? clusters : Array(clusters.prefix(limit))
        let total = clusters.reduce(0) { $0 + $1.count }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("\(question.title) \(total)", systemImage: question.systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.voice)
                Spacer()
                if clusters.count > limit {
                    Button(isOpen ? "접기" : "\(clusters.count - limit)묶음 더") {
                        if isOpen { expanded.remove(question) } else { expanded.insert(question) }
                    }
                    .buttonStyle(.borderless)
                    .font(.body)
                }
            }
            Text(question.use)
                .font(.body)
                .foregroundStyle(.secondary)
            ForEach(shown) { cluster in
                clusterRow(cluster, question: question)
            }
        }
    }

    private func clusterRow(_ cluster: VoiceDigest.Cluster, question: VoiceDigest.Question) -> some View {
        let lead = cluster.lead
        let starred = storeCopy.contains(lead.id)
        return HStack(alignment: .top, spacing: 8) {
            Text(cluster.count > 1 ? "×\(cluster.count)" : "")
                .font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(cluster.count >= 2 && question == .unmet ? .red : Color.voice)
                .frame(minWidth: 28, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(lead.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                let context = [lead.usefulnessLabel, lead.voiceContext.isEmpty ? nil : lead.voiceContext]
                    .compactMap { $0 }.joined(separator: " · ")
                if !context.isEmpty {
                    Text(context)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                // 같은 묶음의 다른 사람들 — 사정이 다르면 뜻도 다르다.
                ForEach(cluster.items.dropFirst().prefix(3), id: \.id) { other in
                    Text("· \(other.text)" + (other.voiceContext.isEmpty ? "" : "  (\(other.voiceContext))"))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            if question == .useful {
                Button {
                    toggleStoreCopy(lead.id)
                } label: {
                    Image(systemName: starred ? "star.fill" : "star")
                        .foregroundStyle(starred ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
                .help(starred ? "스토어 문구 후보에서 빼기" : "스토어 문구 후보로")
                .accessibilityLabel(starred ? "스토어 문구 후보에서 빼기" : "스토어 문구 후보로")
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.voice.opacity(0.06)))
    }

    // MARK: - 동작

    private func toggleStoreCopy(_ id: String) {
        var list = storeCopyRaw.split(separator: "\n").map(String.init)
        if let index = list.firstIndex(of: id) { list.remove(at: index) } else { list.append(id) }
        storeCopyRaw = list.suffix(300).joined(separator: "\n")
    }

    private func copy(_ text: String) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
    }
}
