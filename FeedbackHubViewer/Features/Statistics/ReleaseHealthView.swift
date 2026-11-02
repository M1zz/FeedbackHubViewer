//
//  ReleaseHealthView.swift
//  FeedbackHubViewer
//
//  릴리즈 탭. 한 앱이면 그 앱의 릴리즈 건강 카드, 전체 프로젝트면 앱마다의 판정을
//  빨강 · 노랑 · 초록 순으로 늘어놓는다. 전체에서 알고 싶은 것은 합이 아니라
//  "어느 앱의 새 버전이 문제인가"이기 때문이다. 어느 쪽이든 스토어에 올린 최신 버전과
//  그 상태(판매 중 · 심사 중 · 거절됨 …)를 함께 보인다.
//

import SwiftUI

struct ReleaseHealthView: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var keywords: KeywordStore
    @EnvironmentObject private var connect: AppStoreConnectStore
    /// nil == 전체 프로젝트.
    let project: String?

    #if os(macOS)
    private let contentPadding: CGFloat = 16
    #else
    private let contentPadding: CGFloat = 12
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let project {
                    StoreVersionCard(project: project)
                    ReleaseHealthCard(project: project)
                    StabilizationCard(project: project)
                } else {
                    overview
                    StabilizationOverview()
                }
            }
            .padding(contentPadding)
        }
        .task(id: project == nil) {
            guard project == nil else { return }
            // 차례로 묻는다(한꺼번에 쏘면 시간당 한도를 쓴다). 이미 아는 앱은 묻지 않는다.
            for row in rows.judged + rows.unjudged {
                await connect.loadVersion(bundleID: row.key)
            }
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
                VStack(alignment: .leading, spacing: 0) {
                    Text("판정 없음")
                        .font(.headline)
                    ForEach(Array(rows.unjudged.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { Divider() }
                        unjudgedRow(row)
                    }
                }
                .padding(Platform.cardPadding)
                .cardSurface()
            }
        }
    }

    private func appRow(_ row: Row) -> some View {
        let report = row.report!
        let level = report.verdict.level
        let name = store.displayName(for: row.key)
        var versions = report.latest.version
        if let previous = report.previous { versions += " ← \(previous.version)" }

        return HStack(alignment: .top, spacing: 8) {
        Button {
            store.open(project: row.key, section: .release)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                AppIcon(url: keywords.storeApp(for: row.key)?.iconURL, size: 26)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(name)
                            .font(.body.weight(.semibold))
                            .lineLimit(2)
                        Text(versions)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Spacer(minLength: 4)
                        Tag(text: level.label, systemImage: ReleaseHealthCard.symbol(level),
                            tint: ReleaseHealthCard.tint(level))
                    }
                    if let status = connect.versions[row.key] {
                        StoreVersionTag(status: status)
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
        ClaudeCopyIcon(text: ReleaseHealthCard.claudePrompt(report, appName: name, project: row.key))
        }
    }

    private func unjudgedRow(_ row: Row) -> some View {
        Button {
            store.open(project: row.key, section: .release)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                AppIcon(url: keywords.storeApp(for: row.key)?.iconURL, size: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.displayName(for: row.key))
                        .font(.body.weight(.semibold))
                        .lineLimit(2)
                    if let status = connect.versions[row.key] {
                        StoreVersionTag(status: status)
                    }
                }
                Spacer(minLength: 4)
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 스토어에 올린 최신 버전과 상태. 초록(나가 있음) · 주황(움직이는 중) · 빨강(막힘).
struct StoreVersionTag: View {
    let status: AppVersionStatus
    var font: Font = .body

    var body: some View {
        Tag(text: "v\(status.version) · \(status.stateLabel)", systemImage: "shippingbox",
            tint: tint, font: font)
    }

    private var tint: Color {
        switch status.tone {
        case .live: return .green
        case .moving: return .orange
        case .blocked: return .red
        }
    }
}

/// 한 앱의 릴리즈 탭 맨 위. 건강 판정은 사용 이벤트에서, 이것은 App Store Connect 에서 온다.
private struct StoreVersionCard: View {
    @EnvironmentObject private var connect: AppStoreConnectStore
    let project: String
    /// 물어본 앱. 답을 못 받은 것과 아직 묻는 중인 것을 가른다.
    @State private var askedProject: String?

    var body: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            Label("스토어 상태", systemImage: "shippingbox")
                .font(.headline)
            if let status = connect.versions[project] {
                StoreVersionTag(status: status, font: .body.weight(.semibold))
            } else {
                Text(emptyMessage)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Platform.cardPadding)
        .cardSurface()
        .task(id: project) {
            await connect.loadVersion(bundleID: project)
            askedProject = project
        }
    }

    private var emptyMessage: String {
        if !connect.isConfigured { return "App Store Connect 키를 넣으면 보입니다." }
        return askedProject == project ? "스토어에서 버전을 찾지 못했습니다." : "확인하는 중입니다."
    }
}
