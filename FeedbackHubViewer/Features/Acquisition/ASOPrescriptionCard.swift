//
//  ASOPrescriptionCard.swift
//  FeedbackHubViewer
//
//  검색 처방 — 키워드 필드에서 뺄 것과 넣을 것(`ASOPrescription`).
//

import SwiftUI

// MARK: - 검색 처방

/// 키워드 필드에서 무엇을 빼고 무엇을 넣을지. 새 필드를 채운 편집기로 바로 연다.
struct ASOPrescriptionCard: View {
    @EnvironmentObject private var connect: AppStoreConnectStore
    let project: String
    let aso: ASOPrescription

    @State private var isEditing = false
    @State private var showsWhy = false

    var body: some View {
        Card(title: "검색 처방 (\(aso.locale))", systemImage: "magnifyingglass") {
            VStack(alignment: .leading, spacing: 10) {
                Text(summary)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                if aso.swaps.isEmpty && aso.dropsOnly.isEmpty {
                    Text("지금 필드에서 바꿀 단어를 찾지 못했습니다. 잰 순위와 경쟁 앱 이름으로는 이게 최선이에요.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(aso.swaps) { swap in
                            swapRow(swap)
                        }
                        ForEach(aso.dropsOnly) { removal in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(removal.term).strikethrough().foregroundStyle(.red)
                                Text("빼기").foregroundStyle(.secondary)
                            }
                            .font(.body)
                        }
                    }
                }

                if let hint = aso.subtitleHint {
                    Label(hint, systemImage: "text.badge.star")
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if aso.hasChange {
                    HStack {
                        Button("이 필드로 고치기") { isEditing = true }
                            .buttonStyle(.borderedProminent)
                        CopyButton(text: aso.proposedField)
                    }
                    DisclosureGroup("왜 이렇게 바꾸나 · 새 필드 전문", isExpanded: $showsWhy) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(aso.swaps) { swap in
                                if let from = swap.from {
                                    Text("'\(from.term)' 빼기: \(from.reason)")
                                }
                                Text("'\(swap.to.term)' 넣기: \(swap.to.reason)")
                            }
                            ForEach(aso.dropsOnly) { Text("'\($0.term)' 빼기: \($0.reason)") }
                            Text("새 필드 (\(aso.proposedField.count)/\(StoreMetadata.Limit.keywords)자)")
                                .font(.body.weight(.semibold))
                                .padding(.top, 4)
                            Text(aso.proposedField)
                                .textSelection(.enabled)
                        }
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                    }
                    .font(.body)
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            if let metadata = connect.metadata[project]?.value {
                MetadataEditor(project: project, metadata: metadata, locale: aso.locale,
                               proposedKeywords: aso.proposedField) { isEditing = false }
            }
        }
    }

    private var summary: String {
        var text = "추적하는 검색어 \(aso.trackedCount)개 중 \(aso.rankedCount)개에 잡히고, 상위 10 안은 \(aso.topTen.count)개"
        text += aso.topTen.isEmpty ? "입니다." : "(\(aso.topTen.prefix(3).joined(separator: ", ")))입니다."
        return text
    }

    private func swapRow(_ swap: ASOPrescription.Swap) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let from = swap.from {
                Text(from.term).strikethrough().foregroundStyle(.red)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
            } else {
                Image(systemName: "plus").foregroundStyle(.secondary)
            }
            Text(swap.to.term).foregroundStyle(.green).fontWeight(.semibold)
        }
        .font(.body)
    }
}
