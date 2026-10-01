//
//  DataSourcesPanel.swift
//  FeedbackHubViewer
//
//  허브가 읽는 곳을 한 자리에 — 무엇을 언제 받았고, 지금 무엇을 받는 중이고, 무엇이
//  실패했는지. 그리고 그 전부를 새로 받는 단추 하나.
//
//  읽는 곳은 셋이다. CloudKit(피드백 · 사용 통계), App Store Connect(리뷰 · 판매 · 상품 ·
//  노출 · 링크 출처 · 스토어 문구), App Store 검색(키워드 순위). 예전에는 새로고침이
//  CloudKit 만 읽어서, 리뷰가 왜 그대로인지는 리뷰 화면의 작은 단추를 찾아야 알았다.
//

import SwiftUI

/// 손으로 누른 새로고침. 툴바 단추 · ⌘R · 당겨서 새로고침이 모두 이것을 부른다.
///
/// 자동 갱신(1분)은 CloudKit 만 읽는다 — App Store Connect 리포트를 1분마다 받을
/// 까닭이 없고, 시간당 한도도 있다.
@MainActor
enum HubRefresh {
    /// CloudKit 이 끝날 때까지만 기다린다. App Store Connect 는 링크 출처처럼 1분 걸리는
    /// 것이 있어, 당겨서 새로고침의 바퀴를 그만큼 붙잡아 두지 않게 뒤에서 받는다.
    static func now(_ store: FeedbackStore, _ connect: AppStoreConnectStore) async {
        let project = store.selectedProject
        Task { await connect.refreshAll(project: project) }
        await store.load()
    }
}

/// 지금 새로고침. CloudKit 을 읽는 중에는 막는다.
struct RefreshButton: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var connect: AppStoreConnectStore

    var body: some View {
        Button {
            Task { await HubRefresh.now(store, connect) }
        } label: {
            Label("새로고침", systemImage: "arrow.clockwise")
        }
        .disabled(store.isRefreshing)
        .help("피드백 · 사용 통계 · 리뷰 · 판매 · 유입을 모두 새로 받습니다 (⌘R)")
    }
}

/// 읽는 곳마다 한 줄.
struct DataSourcesPanel: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var connect: AppStoreConnectStore
    @EnvironmentObject private var keywords: KeywordStore

    private var project: String? {
        store.selectedProject == Feedback.unclassifiedProject ? nil : store.selectedProject
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("데이터 상태")
                        .font(.title3.weight(.semibold))
                    Text(project.map { store.displayName(for: $0) } ?? "전체 프로젝트")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                RefreshButton()
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.borderedProminent)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { row in
                    SourceRowView(row: row)
                    if row.id != rows.last?.id { Divider() }
                }
            }

            if !connect.isConfigured {
                HStack {
                    Text("App Store Connect 키를 넣으면 리뷰 · 판매 · 유입도 여기서 함께 받습니다.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    OpenSettingsButton(title: "키 설정")
                }
            } else if project == nil {
                Text("앱을 고르면 그 앱의 리뷰 · 상품 · 노출 · 링크 출처도 여기에 나옵니다.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(minWidth: 380, idealWidth: 440)
    }

    // MARK: - 줄

    private var rows: [SourceRow] {
        var rows: [SourceRow] = [cloudKitRow]
        if connect.isConfigured {
            if let project { rows += projectRows(project) }
            if connect.credentials?.hasVendorNumber == true {
                rows.append(SourceRow(
                    id: "sales", name: "판매 (최근 \(AppStoreConnectStore.salesDays)일)", systemImage: "wonsign.circle",
                    state: connect.isLoadingSales ? .loading(nil)
                        : connect.salesError.map(SourceRow.State.failed)
                        ?? .fetched(connect.fetchedAt["sales"]),
                    refresh: { Task { await connect.loadSales(force: true) } }))
            }
            if connect.subscriptionEvents != nil || connect.isLoadingSubscriptionEvents {
                rows.append(SourceRow(
                    id: "subscriptionEvents", name: "구독 이벤트", systemImage: "repeat.circle",
                    state: connect.isLoadingSubscriptionEvents ? .loading(nil)
                        : connect.subscriptionEventsError.map(SourceRow.State.failed)
                        ?? .fetched(connect.fetchedAt["subscriptionEvents"]),
                    refresh: { Task { await connect.loadSubscriptionEvents(force: true) } }))
            }
        }
        if !keywords.history.keywords.isEmpty { rows.append(keywordRow) }
        return rows
    }

    private var cloudKitRow: SourceRow {
        let state: SourceRow.State
        if store.isRefreshing {
            state = .loading(store.refreshProgress?.text)
        } else if let error = store.errorMessage {
            state = .failed(error)
        } else {
            state = .fetched(store.lastUpdated)
        }
        return SourceRow(id: "cloudkit", name: "피드백 · 사용 통계", systemImage: "icloud",
                         state: state, refresh: { Task { await store.load() } })
    }

    private func projectRows(_ project: String) -> [SourceRow] {
        let feed = connect.reviewFeeds[project]
        let reviewState: SourceRow.State = feed?.isLoading == true ? .loading(nil)
            : feed?.error.map(SourceRow.State.failed) ?? .fetched(feed?.fetchedAt)

        let catalogState: SourceRow.State
        switch connect.catalogs[project] {
        case .loading?: catalogState = .loading(nil)
        case .failed(let message)?: catalogState = .failed(message)
        default: catalogState = .fetched(connect.fetchedAt["catalog:\(project)"])
        }

        return [
            SourceRow(id: "reviews", name: "리뷰", systemImage: "star.bubble", state: reviewState,
                      refresh: { Task { await connect.loadReviews(bundleID: project, force: true) } }),
            SourceRow(id: "catalog", name: "앱 내 구입 상품", systemImage: "bag", state: catalogState,
                      refresh: { Task { await connect.loadCatalog(bundleID: project, force: true) } }),
            SourceRow(id: "metadata", name: "스토어 문구", systemImage: "text.alignleft",
                      state: Self.state(connect.metadata[project], fetched: connect.fetchedAt["metadata:\(project)"]),
                      refresh: { Task { await connect.loadMetadata(bundleID: project, force: true) } }),
            SourceRow(id: "funnel", name: "노출 · 전환", systemImage: "chart.bar",
                      state: Self.state(connect.funnels[project], fetched: connect.fetchedAt["funnel:\(project)"]),
                      refresh: { Task { await connect.loadFunnel(bundleID: project, force: true) } }),
            SourceRow(id: "referrals", name: "누가 내 앱을 링크했나", systemImage: "link",
                      state: Self.state(connect.referrals[project], fetched: connect.fetchedAt["referrals:\(project)"],
                                        loadingNote: "30초~1분"),
                      refresh: { Task { await connect.loadReferrals(bundleID: project, force: true) } }),
        ]
    }

    private var keywordRow: SourceRow {
        let state: SourceRow.State
        if keywords.isChecking {
            state = .loading(keywords.progress.map { "\($0.done)/\($0.total) · \($0.term)" })
        } else if let error = keywords.errorMessage {
            state = .failed(error)
        } else {
            state = .fetched(keywords.history.lastCheckedAt)
        }
        // 키워드 하나에 3초씩이라 몇 분 걸린다. 그래서 모두 새로고침에는 넣지 않고
        // 여기서만 따로 누른다(하루 한 번은 저절로 돈다).
        return SourceRow(id: "keywords", name: "키워드 순위", systemImage: "magnifyingglass",
                         note: "하루 한 번 저절로 확인 · 모두 새로고침에는 빠짐",
                         state: state,
                         refresh: { keywords.check(bundleIds: store.allProjectKeys) })
    }

    private static func state<Value>(_ load: AppStoreConnectStore.LoadState<Value>?, fetched: Date?,
                                     loadingNote: String? = nil) -> SourceRow.State {
        switch load {
        case .loading?: return .loading(loadingNote)
        case .failed(let message)?: return .failed(message)
        default: return .fetched(fetched)
        }
    }
}

/// 읽는 곳 한 줄의 모양.
struct SourceRow: Identifiable {
    enum State {
        case loading(String?)
        case failed(String)
        /// nil 이면 아직 한 번도 새로 받은 적이 없다.
        case fetched(Date?)
    }

    let id: String
    let name: String
    let systemImage: String
    var note: String? = nil
    let state: State
    let refresh: () -> Void

    /// 이보다 묵으면 눈에 띄게.
    static let staleAfter: TimeInterval = 24 * 60 * 60
}

private struct SourceRowView: View {
    let row: SourceRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: row.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(.body.weight(.medium))
                status
                if let note = row.note {
                    Text(note)
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if case .loading = row.state {
                ProgressView().controlSize(.small)
            } else {
                Button(action: row.refresh) {
                    Label("이것만 다시 받기", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("\(row.name)만 다시 받습니다")
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var status: some View {
        switch row.state {
        case .loading(let note):
            Text(note.map { "받는 중 · \($0)" } ?? "받는 중…")
                .font(.body)
                .foregroundStyle(Color.accentColor)
                .monospacedDigit()
        case .failed(let message):
            Text("실패 · \(message)")
                .font(.body)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        case .fetched(let date?):
            let stale = Date().timeIntervalSince(date) > SourceRow.staleAfter
            Text("\(AppFormat.relative(date)) 받음" + (stale ? " · 오래됨" : ""))
                .font(.body)
                .foregroundStyle(stale ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
        case .fetched(nil):
            Text("아직 받지 않음 · 저장된 것을 보여 주는 중일 수 있음")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
}

/// 툴바의 상태 줄을 누르면 데이터 상태 칸이 열린다.
struct DataStatusButton: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var connect: AppStoreConnectStore
    @EnvironmentObject private var keywords: KeywordStore
    @State private var isShowing = false

    var body: some View {
        Button {
            isShowing.toggle()
        } label: {
            RefreshStatus()
        }
        .buttonStyle(.plain)
        .help("무엇을 언제 받았는지 봅니다")
        .popover(isPresented: $isShowing, arrowEdge: .bottom) {
            DataSourcesPanel()
                .environmentObject(store)
                .environmentObject(connect)
                .environmentObject(keywords)
        }
    }
}
