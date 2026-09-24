//
//  ProjectComparisonView.swift
//  FeedbackHubViewer
//
//  전체 프로젝트의 통계 — 합이 아니라 **나란히 세운 순위**다.
//
//  앱 여러 개의 설치를 더한 숫자는 어느 앱에 대해서도 아무것도 말하지 않는다.
//  키보드 5,000대와 알림 앱 2,000대를 합친 7,000대는 할 일을 알려 주지 않지만,
//  "어느 앱이 가장 많이 깔렸고, 어느 앱이 가장 자주 쓰이고, 어느 앱이 크는
//  중인가"는 다음에 어디에 시간을 쓸지를 알려 준다. 그래서 이 화면의 모든 카드는
//  한 지표로 앱들을 줄 세운 것이다.
//
//  숫자는 한 프로젝트 화면(`StatisticsDashboard`)과 같은 계산에서 나온다 —
//  여기서 3위인 앱을 열면 같은 숫자가 보여야 한다.
//

import SwiftUI

struct ProjectComparisonView: View {
    @EnvironmentObject private var store: FeedbackStore

    #if os(macOS)
    private let tileColumns = [GridItem(.adaptive(minimum: 200), spacing: 10)]
    private let sectionSpacing: CGFloat = 20
    private let contentPadding: CGFloat = 16
    #else
    private let tileColumns = [GridItem(.flexible(), spacing: 10),
                               GridItem(.flexible(), spacing: 10)]
    private let sectionSpacing: CGFloat = 14
    private let contentPadding: CGFloat = 12
    #endif

    /// 고착도는 MAU가 이보다 적은 앱을 줄 세우지 않는다. 한 달에 세 명 쓰는 앱이
    /// 매일 오는 한 사람 덕에 1위가 되면, 그 순위는 앱이 아니라 그 사람을 잰 것이다.
    private static let stickinessFloor = 20

    var body: some View {
        let rows = self.rows
        ScrollView {
            VStack(alignment: .leading, spacing: sectionSpacing) {
                if rows.isEmpty {
                    Card(title: "앱별 비교", systemImage: "chart.bar.xaxis") {
                        Text("아직 사용 통계를 보낸 앱이 없습니다. 앱이 UsageSnapshot / UsageEvent를 보내기 시작하면 앱마다 줄 세워 여기 나옵니다.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    leaders(rows)
                    ranking(rows, title: "가장 많이 설치된 앱", systemImage: "iphone",
                            note: "지금 사용 중인 기기(스냅샷을 보낸 설치) 수입니다. 지운 기기는 남지 않아요.") {
                        Metric(value: Double($0.installs), text: "\($0.installs)대",
                               hint: "최근 30일 활성 \($0.active30)명")
                    }
                    ranking(rows, title: "가장 활발한 앱 (MAU)", systemImage: "person.3",
                            note: "최근 30일 안에 이벤트를 보낸 서로 다른 설치 수입니다. 이벤트를 안 보내는 앱은 여기서 0이에요.") {
                        Metric(value: Double($0.mau), text: "\($0.mau)명",
                               hint: "주간 \($0.wau)명 · 일간 \($0.dau)명")
                    }
                    ranking(rows, title: "가장 빨리 크는 앱 (최근 7일 신규)", systemImage: "sparkles",
                            note: "최근 7일에 처음 설치된 기기 수입니다.") {
                        Metric(value: Double($0.new7), text: "\($0.new7)대",
                               hint: "지난주 \($0.previousNew7)대" + Self.change($0.new7, $0.previousNew7))
                    }
                    ranking(rows.filter { $0.mau >= Self.stickinessFloor },
                            title: "가장 자주 여는 앱 (고착도)", systemImage: "arrow.clockwise",
                            note: "평균 DAU ÷ MAU — 한 달에 쓴 사람이 30일 중 며칠 오는가입니다. 월간 활성이 \(Self.stickinessFloor)명 미만인 앱은 한두 사람이 순위를 뒤집어서 빼었어요. 낮다고 나쁜 게 아니라 앱의 성격입니다.") {
                        guard let ratio = $0.stickiness else { return nil }
                        return Metric(value: ratio, text: String(format: "%.0f%%", (ratio * 100).rounded()),
                                      hint: String(format: "한 달에 평균 %.1f일", ratio * 30))
                    }
                    ranking(rows, title: "지난주보다 많이 쓰는 앱 (WAU 증감)", systemImage: "arrow.up.arrow.down",
                            note: "최근 7일 활성 사용자에서 그 앞 7일을 뺀 값입니다. 줄어든 앱은 막대를 주황으로 그렸어요.") {
                        guard $0.wau > 0 || $0.previousWau > 0 else { return nil }
                        let delta = $0.wau - $0.previousWau
                        return Metric(value: Double(delta), text: (delta > 0 ? "+" : "") + "\(delta)명",
                                      hint: "이번 주 \($0.wau)명 · 지난주 \($0.previousWau)명" + Self.change($0.wau, $0.previousWau))
                    }
                    ranking(rows, title: "피드백이 많은 앱", systemImage: "text.bubble",
                            note: "접수된 피드백 전체 건수입니다.") {
                        guard $0.feedback > 0 else { return nil }
                        return Metric(value: Double($0.feedback), text: "\($0.feedback)건",
                                      hint: $0.rating.map { String(format: "평균 별점 %.2f", $0) } ?? "별점 없음")
                    }
                }
            }
            .padding(contentPadding)
        }
    }

    // MARK: - 한 앱의 숫자

    private struct Row: Identifiable {
        var id: String { key }
        let key: String
        let name: String
        let installs: Int
        let active30: Int
        let new7: Int
        let previousNew7: Int
        let dau: Int
        let wau: Int
        let previousWau: Int
        let mau: Int
        let stickiness: Double?
        let feedback: Int
        let rating: Double?
    }

    private var rows: [Row] {
        let feedbackByProject = Dictionary(grouping: store.allFeedback, by: \.projectKey)
        return store.allProjectKeys
            .filter { $0 != Feedback.unclassifiedProject }
            .compactMap { key -> Row? in
                let usage = store.usage(for: key)
                let items = feedbackByProject[key] ?? []
                guard usage.hasUsageData || !items.isEmpty else { return nil }
                let active = store.activeUsers(for: key)
                let ratings = items.compactMap(\.rating)
                return Row(key: key,
                           name: usage.displayName,
                           installs: usage.installs,
                           active30: usage.active30,
                           new7: usage.new7,
                           previousNew7: usage.previousNew7,
                           dau: active.day.current,
                           wau: active.week.current,
                           previousWau: active.week.previous,
                           mau: active.month.current,
                           stickiness: active.stickiness,
                           feedback: items.count,
                           rating: ratings.isEmpty ? nil : Double(ratings.reduce(0, +)) / Double(ratings.count))
            }
    }

    // MARK: - 1위만 모은 한 줄

    /// 순위 카드마다 맨 위 한 줄만 뽑아 둔 것. 화면을 열자마자 답이 보이고,
    /// 까닭은 아래 카드에서 읽는다.
    private func leaders(_ rows: [Row]) -> some View {
        let sticky = rows.filter { $0.mau >= Self.stickinessFloor && $0.stickiness != nil }
        return LazyVGrid(columns: tileColumns, spacing: 10) {
            LeaderTile(title: "가장 많이 설치됨", systemImage: "iphone", tint: .accentColor,
                       winner: rows.max { $0.installs < $1.installs }.map { ($0.name, "\($0.installs)대") })
            LeaderTile(title: "가장 활발함 (MAU)", systemImage: "bolt.fill", tint: .blue,
                       winner: rows.filter { $0.mau > 0 }.max { $0.mau < $1.mau }.map { ($0.name, "\($0.mau)명") })
            LeaderTile(title: "가장 빨리 큼 (7일 신규)", systemImage: "sparkles", tint: .green,
                       winner: rows.filter { $0.new7 > 0 }.max { $0.new7 < $1.new7 }.map { ($0.name, "\($0.new7)대") })
            LeaderTile(title: "가장 자주 엶 (고착도)", systemImage: "arrow.clockwise", tint: .teal,
                       winner: sticky.max { ($0.stickiness ?? 0) < ($1.stickiness ?? 0) }
                        .map { ($0.name, String(format: "%.0f%%", (($0.stickiness ?? 0) * 100).rounded())) })
        }
    }

    // MARK: - 순위 카드

    private struct Metric {
        let value: Double
        let text: String
        let hint: String
    }

    /// 한 지표로 줄 세운 카드. `metric`이 nil인 앱은 그 지표를 말할 수 없는
    /// 앱이라 줄에서 빠진다 — 0으로 세우면 "꼴찌"가 되는데, 그건 모름이다.
    private func ranking(_ rows: [Row], title: String, systemImage: String, note: String,
                         metric: (Row) -> Metric?) -> some View {
        let ranked = rows.compactMap { row in metric(row).map { (row: row, metric: $0) } }
            .sorted { $0.metric.value > $1.metric.value }
        let peak = ranked.map { abs($0.metric.value) }.max() ?? 0
        return Card(title: title, systemImage: systemImage) {
            if ranked.isEmpty {
                Text("줄 세울 앱이 없습니다.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(ranked.enumerated()), id: \.element.row.id) { index, entry in
                        rankRow(rank: index + 1, entry.row, entry.metric,
                                ratio: peak > 0 ? abs(entry.metric.value) / peak : 0)
                    }
                }
            }
            Text(note)
                .font(.body)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func rankRow(rank: Int, _ row: Row, _ metric: Metric, ratio: Double) -> some View {
        let content = VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(rank)")
                    .font(.body.monospacedDigit().weight(.semibold))
                    .foregroundStyle(rank == 1 ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .frame(minWidth: 22, alignment: .trailing)
                Text(row.name)
                    .font(.body.weight(rank == 1 ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(metric.text)
                    .font(.body.monospacedDigit().weight(.semibold))
            }
            MeterBar(ratio: ratio, tint: metric.value < 0 ? .orange : .accentColor)
                .padding(.leading, 30)
            Text(metric.hint)
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(.leading, 30)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())

        #if os(macOS)
        // 맥은 사이드바가 곧 이 값을 따라가므로, 줄을 누르면 그 앱의 통계로 넘어간다.
        return Button { store.selectedProject = row.key } label: { content }
            .buttonStyle(.plain)
            .help("\(row.name) 통계 열기")
        #else
        return content
        #endif
    }

    /// "(▲12%)" — 견줄 것이 없으면 아무 말도 하지 않는다.
    private static func change(_ current: Int, _ previous: Int) -> String {
        guard previous > 0, current != previous else { return "" }
        let ratio = Double(current - previous) / Double(previous)
        return String(format: " (%@%.0f%%)", ratio > 0 ? "▲" : "▼", abs(ratio * 100).rounded())
    }
}

/// 한 지표의 1위. 1위가 없으면(아무도 그 값을 안 보냄) 자리는 지키고 "—".
private struct LeaderTile: View {
    let title: String
    let systemImage: String
    let tint: Color
    let winner: (name: String, value: String)?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(winner?.name ?? "—")
                .font(.headline)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(winner?.value ?? "아직 없음")
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Platform.tilePadding)
        .cardSurface()
    }
}
