//
//  MarketingReadinessViews.swift
//  FeedbackHubViewer
//
//  마케팅 칸의 세 판정 — 홍보할 채비가 됐나(서비스 숙성도), 자료가 나갔나(배포), 사람을 데려왔나
//  (캠페인). 한 앱이면 세 카드, 전체 앱이면 앱마다 한 줄.
//
//  판정이 먼저, 항목 전부는 접어 둔다(허브 화면의 원칙).
//

import SwiftUI

// MARK: - 홍보 채비

struct MarketingReadinessCard: View {
    @ObservedObject private var portfolio = PortfolioStore.shared
    let project: String

    var body: some View {
        Card(title: "홍보 채비 · 서비스 숙성도", systemImage: "checklist") {
            if let app = portfolio.app(for: project), let readiness = app.readiness {
                content(readiness)
                if let page = app.introPage { introPage(page) }
            } else if portfolio.app(for: project) != nil {
                Text("app-portfolio 에 이 앱은 있지만 홍보 칸을 아직 재지 않았어요. sync-service-maturity.py 를 돌리면 채워져요.")
                    .font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else if portfolio.isLoading {
                ProgressView().controlSize(.small)
            } else {
                Text("app-portfolio 에서 이 앱(번들 ID)을 못 찾았어요. 앱 JSON 의 bundleId 가 허브의 키와 같은지 보세요.")
                    .font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func content(_ readiness: MarketingReadiness) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(readiness.headline)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint(readiness))
            Spacer()
            if !readiness.isUnknown {
                Text("\(readiness.present)/\(readiness.measured)")
                    .font(.title3.monospacedDigit().weight(.semibold))
            }
        }
        Label("영상 만들기 도구: \(readiness.videoLine)", systemImage: "video")
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)
        let missing = readiness.missing
        if !missing.isEmpty {
            Text("먼저 할 것")
                .font(.headline)
                .padding(.top, 4)
            ForEach(missing.prefix(3), id: \.key) { item in
                Label(item.todo, systemImage: "arrow.right.circle")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        DisclosureGroup("항목 전부") {
            ForEach(MarketingReadiness.Group.allCases, id: \.self) { group in
                let rows = readiness.items.filter { $0.item.group == group }
                if !rows.isEmpty {
                    Text(group.rawValue).font(.headline).padding(.top, 6)
                    ForEach(rows, id: \.item.key) { row in
                        HStack {
                            Image(systemName: row.value == true ? "checkmark.circle.fill"
                                  : row.value == false ? "circle" : "questionmark.circle")
                                .foregroundStyle(row.value == true ? .green : .secondary)
                            Text(row.item.name).font(.body)
                            Spacer()
                            Text(row.value == true ? "있음" : row.value == false ? "없음" : "모름")
                                .font(.body).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let at = readiness.evaluatedAt {
                Text("측정 \(at) · \(PortfolioStore.shared.source?.rawValue ?? "")")
                    .font(.body).foregroundStyle(.secondary).padding(.top, 4)
            }
        }
        .font(.body)
    }

    /// 소개 페이지 — 스토어 밖에서 앱을 처음 보는 자리. 판정 한 줄, 빠진 것, 열기.
    @ViewBuilder
    private func introPage(_ page: PortfolioApp.IntroPage) -> some View {
        Divider()
        HStack(alignment: .firstTextBaseline) {
            Label(page.headline, systemImage: "doc.richtext")
                .font(.headline)
                .foregroundStyle(page.set == false || page.reachable == false ? Color.orange : .primary)
            Spacer()
            if let link = page.url.flatMap(URL.init(string:)) {
                Link("열기", destination: link).font(.body)
            }
        }
        let missing = page.checks.filter { $0.value == false }.map(\.name)
        if page.set != false, !missing.isEmpty {
            Text("빠진 것: " + missing.joined(separator: " · "))
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func tint(_ readiness: MarketingReadiness) -> Color {
        if readiness.isUnknown { return .secondary }
        let ratio = Double(readiness.present) / Double(max(readiness.measured, 1))
        return ratio >= 0.75 ? .green : ratio >= 0.4 ? .orange : .red
    }
}

// MARK: - 배포

struct MarketingDistributionCard: View {
    @ObservedObject private var marketing = MarketingStore.shared
    @ObservedObject private var portfolio = PortfolioStore.shared
    let project: String

    var body: some View {
        let items = marketing.items(for: project)
        let posted = items.filter { $0.stage == .posted }.sorted { ($0.postedAt ?? .distantPast) > ($1.postedAt ?? .distantPast) }
        let ready = items.filter { $0.stage == .ready }
        let awaiting = items.filter { $0.needsConfirmation() }
        let records = (portfolio.app(for: project)?.marketing ?? [:]).filter { $0.value.posted == true }

        Card(title: "자료 배포", systemImage: "paperplane") {
            Text(headline(posted: posted.count + records.count, ready: ready.count, awaiting: awaiting.count))
                .font(.title3.weight(.semibold))
                .foregroundStyle(awaiting.isEmpty ? (posted.isEmpty && records.isEmpty ? Color.orange : .green) : .red)
            Text("올라감 \(posted.count) · 자료 완성(대기) \(ready.count) · 답할 것 \(awaiting.count)"
                 + (posted.first?.postedAt).map { " · 마지막 \(AppFormat.relative($0))" }.orEmpty)
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
            if !posted.isEmpty || !records.isEmpty {
                DisclosureGroup("올린 것") {
                    ForEach(posted.prefix(20)) { item in
                        postRow(title: "\(item.channel) \(item.kind.label) · \(item.title)",
                                date: item.postedAt.map(AppFormat.dateTime), url: item.postURL)
                    }
                    ForEach(records.sorted { $0.key < $1.key }, id: \.key) { channel, post in
                        postRow(title: "\(post.subreddit ?? channel) · app-portfolio 기록",
                                date: post.recordedAt, url: post.url ?? "")
                    }
                }
                .font(.body)
            }
        }
    }

    private func headline(posted: Int, ready: Int, awaiting: Int) -> String {
        if awaiting > 0 { return "올렸는지 답할 것 \(awaiting)개" }
        if posted == 0 { return ready > 0 ? "아직 하나도 안 나갔어요 — 완성 \(ready)개 대기" : "나간 자료가 없어요" }
        return "\(posted)개 나갔어요"
    }

    @ViewBuilder
    private func postRow(title: String, date: String?, url: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body).fixedSize(horizontal: false, vertical: true)
                if let date { Text(date).font(.body).foregroundStyle(.secondary) }
            }
            Spacer()
            if let link = URL(string: url), !url.isEmpty {
                Link("열기", destination: link).font(.body)
            } else {
                Text("주소 없음").font(.body).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - 캠페인

struct MarketingCampaignCard: View {
    @EnvironmentObject private var connect: AppStoreConnectStore
    @EnvironmentObject private var keywords: KeywordStore
    @ObservedObject private var marketing = MarketingStore.shared
    let project: String

    var body: some View {
        Card(title: "캠페인 추적", systemImage: "scope") {
            if marketing.providerToken.isEmpty {
                ProviderTokenField()
            } else if keywords.trackId(for: project) == nil {
                Text("이 앱이 App Store 와 이어지지 않아 캠페인 링크를 만들 수 없어요. 앱 목록에서 오른쪽 클릭 → App Store 링크로 잇기.")
                    .font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                results
            }
        }
        .task(id: project) {
            if connect.isConfigured { await connect.loadReferrals(bundleID: project) }
        }
    }

    @ViewBuilder
    private var results: some View {
        let items = marketing.items(for: project).filter { $0.stage == .posted }
        switch connect.referrals[project] {
        case .loaded(.ready(_, let report))?:
            let byToken = report.campaigns
            let mine = items.map { ($0, byToken[$0.campaignToken]) }
            let brought = mine.compactMap { $0.1 }.reduce(0) { $0 + $1.firstDownloads }
            Text(brought > 0 ? "캠페인 링크로 첫 다운로드 \(brought)회 (최근 \(report.days)일)"
                 : report.hasCampaignColumn ? "캠페인 링크로 들어온 다운로드가 아직 없어요"
                 : "리포트에 아직 캠페인 기록이 없어요")
                .font(.title3.weight(.semibold))
                .foregroundStyle(brought > 0 ? .green : .secondary)
            Text("활동마다 캠페인 링크를 쓰면(편집 화면의 \"캠페인 링크\") 그 글이 데려온 사람이 여기서 갈려요. 리포트는 하루 이틀 늦게 쌓여요.")
                .font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(mine.filter { $0.1 != nil }.sorted { ($0.1?.firstDownloads ?? 0) > ($1.1?.firstDownloads ?? 0) }, id: \.0.id) { item, tally in
                HStack {
                    Text("\(item.channel) · \(item.title)").font(.body).lineLimit(1)
                    Spacer()
                    Text("다운로드 \(tally?.firstDownloads ?? 0) · 조회 \(tally?.pageViews ?? 0)")
                        .font(.body.monospacedDigit())
                }
            }
            let others = byToken.filter { token, _ in !items.contains { $0.campaignToken == token } }
            if !others.isEmpty {
                DisclosureGroup("허브 활동이 아닌 캠페인 \(others.count)개") {
                    ForEach(others.sorted { $0.value.firstDownloads > $1.value.firstDownloads }, id: \.key) { token, tally in
                        HStack {
                            Text(token).font(.body.monospaced())
                            Spacer()
                            Text("다운로드 \(tally.firstDownloads) · 조회 \(tally.pageViews)").font(.body.monospacedDigit())
                        }
                    }
                }
                .font(.body)
            }
        case .loading?:
            ProgressView().controlSize(.small)
        case .failed(let message)?:
            Text(message).font(.body).foregroundStyle(.orange)
        default:
            Text(connect.isConfigured ? "분석 리포트 요청이 없어 캠페인을 셀 수 없어요. 스토어 분석 칸에서 리포트 요청을 만드세요."
                 : "App Store Connect 키를 넣으면 캠페인 성과를 셉니다.")
                .font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 제공자 토큰(pt) 입력 — 계정에 하나.
struct ProviderTokenField: View {
    @ObservedObject private var marketing = MarketingStore.shared
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("캠페인을 세려면 제공자 토큰(pt)이 한 번 필요해요")
                .font(.headline)
            Text("App Store Connect → 앱 → 분석 → 획득 → 캠페인 → \"캠페인 링크 생성\" 에서 만든 링크의 pt= 뒤 숫자예요. 계정에 하나라 한 번만 넣으면 모든 앱에 쓰여요.")
                .font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                TextField("예: 123456789 (링크를 통째로 붙여도 됩니다)", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
                Button("저장") {
                    let token = draft.range(of: #"pt=(\d+)"#, options: .regularExpression)
                        .map { String(draft[$0].dropFirst(3)) } ?? draft
                    marketing.providerToken = token
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft.filter(\.isNumber).isEmpty)
            }
        }
    }
}

// MARK: - 전체 앱

/// 앱마다 한 줄 — 채비 · 배포 · 먼저 할 것. 채비가 덜 된 앱이 위.
struct MarketingOverviewCard: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var keywords: KeywordStore
    @ObservedObject private var portfolio = PortfolioStore.shared
    @ObservedObject private var marketing = MarketingStore.shared
    @ObservedObject private var icons = StoreIcons.shared

    var body: some View {
        let rows = store.projectCounts.map(\.key)
            .filter { $0 != Feedback.unclassifiedProject }
            .map { key in (key: key, readiness: portfolio.app(for: key)?.readiness,
                           posted: marketing.items(for: key).filter { $0.stage == .posted }.count,
                           ready: marketing.items(for: key).filter { $0.stage == .ready }.count) }
            .sorted { a, b in
                let ra = a.readiness.map { Double($0.present) / Double(max($0.measured, 1)) } ?? 2
                let rb = b.readiness.map { Double($0.present) / Double(max($0.measured, 1)) } ?? 2
                return ra == rb ? a.key < b.key : ra < rb
            }
        let measured = rows.compactMap(\.readiness).filter { !$0.isUnknown }
        let noPost = rows.filter { $0.posted == 0 }.count

        Card(title: "앱마다 홍보 채비 · 배포", systemImage: "square.grid.2x2") {
            Text("채비가 덜 된 앱이 위 · 나간 자료가 없는 앱 \(noPost)개")
                .font(.body).foregroundStyle(.secondary)
            if measured.isEmpty {
                Text(portfolio.isLoading ? "app-portfolio 읽는 중…" : "app-portfolio 의 홍보 칸이 아직 비어 있어요.")
                    .font(.body).foregroundStyle(.secondary)
            }
            ForEach(rows, id: \.key) { row in
                Button { store.open(project: row.key, section: .marketing) } label: {
                    HStack(alignment: .top, spacing: 10) {
                        AppIcon(url: icons.url(for: row.key, keywords: keywords), size: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.displayName(for: row.key)).font(.body.weight(.semibold))
                            Text(row.readiness?.missing.first.map { "먼저: \($0.name)" } ?? (row.readiness == nil ? "숙성도 없음" : "다 갖춤"))
                                .font(.body).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(row.readiness.map { $0.isUnknown ? "채비 모름" : "채비 \($0.present)/\($0.measured)" } ?? "—")
                                .font(.body.monospacedDigit())
                            Text("나감 \(row.posted) · 대기 \(row.ready)")
                                .font(.body.monospacedDigit())
                                .foregroundStyle(row.posted == 0 ? .orange : .secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 3)
            }
        }
    }
}

private extension Optional where Wrapped == String {
    var orEmpty: String { self ?? "" }
}
