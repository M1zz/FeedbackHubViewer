//
//  ReviewPriorityView.swift
//  FeedbackHubViewer
//
//  전체 프로젝트의 "리뷰" 섹션 — ReviewManager 의 우선순위 대시보드.
//
//  앱마다 위험 · 기회 점수를 내고(`PriorityScorer`), 지금 가장 신경 쓸 앱과 키우면 더 잘
//  될 앱을 맨 위에 적는다. 한 줄을 누르면 그 앱의 리뷰로 간다.
//
//  분석은 누를 때만 돈다. 앱마다 리뷰 · 상품을 차례로 읽어서 몇 분 걸릴 수 있고, App
//  Store Connect 의 시간당 한도도 쓴다. 지난 분석은 디스크에 남아 다음에 켜도 보인다.
//

import SwiftUI

struct ReviewPriorityView: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var purchases: AppStoreConnectStore
    @EnvironmentObject private var keywords: KeywordStore

    @State private var sort: PrioritySort = .priority

    private var projects: [(key: String, name: String)] {
        store.allProjectKeys
            .filter { $0 != Feedback.unclassifiedProject }
            .map { ($0, store.displayName(for: $0)) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let analysis = purchases.priority, !analysis.rows.isEmpty {
                    headline(analysis.rows)
                    legend(analysis)
                    let rows = sort.sorted(analysis.rows)
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        Button {
                            store.open(project: row.id, section: .reviews)
                        } label: {
                            PriorityRowCard(rank: index + 1, row: row, sort: sort,
                                            iconURL: keywords.storeApp(for: row.id)?.iconURL)
                        }
                        .buttonStyle(.plain)
                    }
                } else if !purchases.isAnalyzingPriority {
                    empty
                }
            }
            .padding(ReviewLayout.padding)
        }
    }

    // MARK: 머리

    private var header: some View {
        Card(title: "어느 앱을 먼저 볼까", systemImage: "flag") {
            Text("앱마다 **위험**(돈 버는 앱인데 다운로드 · 평점이 흔들림)과 **기회**(잘 나가고 오르는 중이라 키울 만함)를 0~100으로 냅니다. 우선순위는 둘 중 큰 쪽에 작은 쪽을 조금 더한 값이에요.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            FlowLayout(spacing: 10, lineSpacing: 8) {
                Button {
                    Task { await purchases.analyzePriority(projects: projects) }
                } label: {
                    Label(purchases.priority == nil ? "지금 분석하기" : "다시 분석", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .disabled(purchases.isAnalyzingPriority)

                if purchases.priority != nil {
                    Picker("정렬", selection: $sort) {
                        ForEach(PrioritySort.allCases) { Label($0.rawValue, systemImage: $0.systemImage).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                }

                if purchases.priorityHistory.count > 1 {
                    Menu {
                        ForEach(purchases.priorityHistory) { snapshot in
                            Button {
                                purchases.priority = snapshot
                            } label: {
                                let title = "\(AppFormat.dateTime(snapshot.date)) · 앱 \(snapshot.rows.count)개"
                                if snapshot.id == purchases.priority?.id {
                                    Label(title, systemImage: "checkmark")
                                } else {
                                    Text(title)
                                }
                            }
                        }
                    } label: {
                        Label("분석 기록", systemImage: "clock.arrow.circlepath")
                    }
                    .fixedSize()
                }
            }

            if let progress = purchases.priorityProgress {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(progress)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else if let analysis = purchases.priority {
                Text("\(AppFormat.dateTime(analysis.date))에 낸 점수" + (analysis.id == purchases.priorityHistory.first?.id ? "" : " (지난 기록)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var empty: some View {
        Card(title: "아직 낸 점수가 없습니다", systemImage: "chart.bar.xaxis") {
            Text("\"지금 분석하기\"를 누르면 앱 \(projects.count)개의 리뷰와 최근 \(AppStoreConnectStore.salesDays)일 판매를 모아 점수를 냅니다.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if purchases.credentials?.hasVendorNumber != true {
                Label("판매자 번호가 없어 결제 · 다운로드 신호 없이 리뷰만으로 냅니다. 설정에서 넣을 수 있어요.",
                      systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func headline(_ rows: [PriorityRow]) -> some View {
        let risk = rows.max { $0.risk < $1.risk }
        let opportunity = rows.max { $0.opportunity < $1.opportunity }
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 10)], spacing: 10) {
            if let risk {
                banner(title: "지금 가장 신경 쓸 앱", row: risk, tint: .orange,
                       systemImage: "exclamationmark.triangle.fill",
                       detail: "위험 \(Int(risk.risk)) · 우선순위 \(Int(risk.priority))")
            }
            if let opportunity, opportunity.id != risk?.id, opportunity.opportunity >= 45 {
                banner(title: "키우면 더 잘 될 앱", row: opportunity, tint: .green,
                       systemImage: "arrow.up.right.circle.fill",
                       detail: "기회 \(Int(opportunity.opportunity))")
            }
        }
    }

    private func banner(title: String, row: PriorityRow, tint: Color, systemImage: String, detail: String) -> some View {
        Button {
            store.open(project: row.id, section: .reviews)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title)
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.caption).foregroundStyle(.secondary)
                    Text(row.name).font(.title3.bold()).lineLimit(1)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(tint.opacity(0.25)))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func legend(_ analysis: PriorityAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            FlowLayout(spacing: 12, lineSpacing: 4) {
                legendItem("60 이상", .red, "바로")
                legendItem("35~59", .orange, "지켜보기")
                legendItem("35 미만", .green, "괜찮음")
            }
            if !analysis.usedSales {
                Text("판매 리포트 없이 리뷰만으로 낸 점수입니다.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Text("\"결제 핵심\"은 통화가 섞이지 않게 돈을 낸 인앱 결제 건수로 가립니다. 수익금은 통화별로 따로 적어요.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func legendItem(_ range: String, _ tint: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(tint).frame(width: 8, height: 8)
            Text(range).font(.caption.weight(.semibold))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - 한 줄

private struct PriorityRowCard: View {
    let rank: Int
    let row: PriorityRow
    let sort: PrioritySort
    let iconURL: URL?

    private var score: Double {
        switch sort {
        case .risk: return row.risk
        case .opportunity: return row.opportunity
        case .priority, .purchases: return row.priority
        }
    }

    private var scoreTint: Color {
        score >= 60 ? .red : (score >= 35 ? .orange : .green)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(rank)")
                .font(.title3.monospacedDigit().weight(.heavy))
                .foregroundStyle(.tertiary)
                .frame(minWidth: 26)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    AppIcon(url: iconURL, size: 26)
                    Text(row.name)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("\(Int(score))")
                        .font(.title2.monospacedDigit().weight(.heavy))
                        .foregroundStyle(scoreTint)
                }

                VStack(spacing: 5) {
                    axis("위험", row.risk, .orange)
                    axis("기회", row.opportunity, .green)
                }

                if !row.flags.isEmpty {
                    FlowLayout(spacing: 6, lineSpacing: 4) {
                        ForEach(row.flags, id: \.self) { flag in
                            Tag(text: flag.text, systemImage: flag.systemImage,
                                tint: flag.isBad ? .red : (flag.kind == .money ? .yellow : .green),
                                isCompact: true)
                        }
                    }
                }

                FlowLayout(spacing: 18, lineSpacing: 8) {
                    metric("결제 (30일)", "\(row.paidPurchases)건")
                    metric("수익금", row.proceedsLabel)
                    metric("첫 다운로드", AppFormat.count(row.firstDownloads))
                    metric("추세", trendText, tint: (row.trendPct ?? 0) >= 0 ? .green : .red)
                    metric("최근 평점", ratingText)
                    metric("리뷰", AppFormat.count(row.reviewCount))
                    metric("답 안 함", "\(row.unanswered)", tint: row.unanswered > 0 ? .orange : .primary)
                }
            }
        }
        .padding(Platform.cardPadding)
        .cardSurface()
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }

    private var trendText: String {
        guard let trend = row.trendPct else { return "—" }
        return (trend >= 0 ? "▲ " : "▼ ") + "\(abs(Int(trend)))%"
    }

    private var ratingText: String {
        guard let rating = row.recentRating else { return "—" }
        var text = String(format: "%.2f", rating)
        if let delta = row.ratingDelta { text += String(format: " (%+.2f)", delta) }
        return text
    }

    private func axis(_ label: String, _ value: Double, _ tint: Color) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .leading)
            MeterBar(ratio: value / 100, height: 7, tint: tint.opacity(0.85))
            Text("\(Int(value))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(Int(value))점")
    }

    private func metric(_ label: String, _ value: String, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(tint)
        }
    }
}
