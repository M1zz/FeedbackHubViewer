//
//  ReleaseHealthView.swift
//  FeedbackHubViewer
//
//  릴리즈 탭. 한 앱이면 그 앱의 릴리즈 건강 카드, 전체 프로젝트면 앱마다의 판정을
//  빨강 · 노랑 · 초록 순으로 늘어놓는다. 전체에서 알고 싶은 것은 합이 아니라
//  "어느 앱의 새 버전이 문제인가"이기 때문이다.
//

import SwiftUI

struct ReleaseHealthView: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var keywords: KeywordStore
    /// nil == 전체 프로젝트.
    let project: String?

    #if os(macOS)
    private let contentPadding: CGFloat = 16
    #else
    private let contentPadding: CGFloat = 12
    #endif

    var body: some View {
        ScrollView {
            Group {
                if let project {
                    ReleaseHealthCard(project: project)
                } else {
                    overview
                }
            }
            .padding(contentPadding)
        }
    }

    // MARK: - 전체 프로젝트

    private struct Row: Identifiable {
        let key: String
        let report: ReleaseHealth.Report?
        var id: String { key }
    }

    /// 판정이 있는 앱은 무거운 것부터, 없는 앱은 맨 아래. 같은 단계 안에서는
    /// 받은 차례(어제 DAU 순)를 그대로 둔다.
    private var rows: (judged: [Row], unjudged: [Row]) {
        let all = store.projectCounts
            .map(\.key)
            .filter { $0 != Feedback.unclassifiedProject }
            .map { Row(key: $0, report: store.releaseHealth(for: $0)) }
        let judged = all.enumerated()
            .filter { $0.element.report != nil }
            .sorted { lhs, rhs in
                let l = lhs.element.report!.verdict.level, r = rhs.element.report!.verdict.level
                return l == r ? lhs.offset < rhs.offset : l > r
            }
            .map(\.element)
        return (judged, all.filter { $0.report == nil })
    }

    @ViewBuilder
    private var overview: some View {
        let rows = rows
        VStack(alignment: .leading, spacing: 12) {
            if rows.judged.isEmpty {
                ContentUnavailableView(
                    "판정할 수 있는 앱이 없습니다",
                    systemImage: "stethoscope",
                    description: Text("최근 \(ReleaseHealth.windowDays)일에 버전이 적힌 사용 이벤트를 보낸 앱이 없습니다.")
                )
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.judged.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { Divider() }
                        appRow(row)
                    }
                }
                .padding(Platform.cardPadding)
                .cardSurface()
            }

            if !rows.unjudged.isEmpty {
                // 판정이 없는 것은 괜찮다는 뜻이 아니다 — 초록 사이에 섞지 않는다.
                Text("판정 없음: " + rows.unjudged.map { store.displayName(for: $0.key) }.joined(separator: ", "))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func appRow(_ row: Row) -> some View {
        let report = row.report!
        let level = report.verdict.level
        let name = store.displayName(for: row.key)
        var versions = report.latest.version
        if let previous = report.previous { versions += " ← \(previous.version)" }

        return Button {
            store.open(project: row.key, section: .release)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                AppIcon(url: keywords.storeApp(for: row.key)?.iconURL, size: 26)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(name)
                            .font(.body.weight(.semibold))
                            .lineLimit(1)
                        Text(versions)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Tag(text: level.label, systemImage: ReleaseHealthCard.symbol(level),
                            tint: ReleaseHealthCard.tint(level))
                    }
                    Text(report.verdict.headline)
                        .font(.body)
                        .foregroundStyle(level == .green ? AnyShapeStyle(.secondary)
                                                         : AnyShapeStyle(ReleaseHealthCard.tint(level)))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name), 릴리즈 건강 \(level.label), \(report.verdict.headline)")
    }
}
