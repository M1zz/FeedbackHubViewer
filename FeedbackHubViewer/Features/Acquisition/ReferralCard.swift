//
//  ReferralCard.swift
//  FeedbackHubViewer
//
//  "누가 내 앱을 링크했나" 카드. 새로 링크한 곳과 갑자기 늘어난 곳을 위에, 꾸준히
//  보내는 곳을 그 아래, 링크가 열린 통로(브라우저 · 메모)는 접어 둔다.
//  계산은 `ReferralDetection`, 받는 일은 `AppStoreConnectStore+Referrals.swift`.
//
//  유입 지도가 없는 앱에도 뜬다 — 지도는 앱마다 손으로 쓰지만, 이 카드는 App Store
//  리포트만 있으면 된다.
//

import SwiftUI

struct ReferralCard: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var connect: AppStoreConnectStore
    let project: String

    @State private var showsPassages = false

    var body: some View {
        Card(title: "누가 내 앱을 링크했나", systemImage: "link") {
            content
        }
        .task(id: project) { await connect.loadReferrals(bundleID: project) }
    }

    @ViewBuilder
    private var content: some View {
        if !connect.isConfigured {
            note("App Store Connect 키를 넣으면 App Store 상세 리포트에서 이 앱으로 사람을 보낸 웹사이트와 앱을 찾습니다.")
        } else {
            switch connect.referrals[project] {
            case nil, .loading?:
                ProgressView("상세 리포트 받는 중… (30초~1분)")
            case .failed(let message)?:
                note(message)
                Button("다시 읽기") { Task { await connect.loadReferrals(bundleID: project, force: true) } }
            case .loaded(.noRequest)?:
                note("App Store 분석 리포트 요청이 없습니다. 한 번 만들면 1~2일 뒤부터 쌓입니다. 노출 · 전환 카드와 같은 요청을 씁니다.")
                Button("리포트 요청 만들기") { Task { await connect.requestAnalytics(bundleID: project) } }
            case .loaded(.ready(let detection, let report))?:
                if report.instances == 0 {
                    note("요청은 있지만 상세 리포트 파일이 아직 없습니다. 1~2일 걸립니다.")
                } else {
                    ready(detection, report)
                }
            }
        }
    }

    // MARK: - 결과

    private func ready(_ detection: ReferralDetection, _ report: ReferralReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                StateDot(state: detection.alerts.isEmpty ? .healthy : .watch)
                Text(detection.headline)
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !detection.alerts.isEmpty {
                Label("새로 링크한 곳에 가서 어떤 글인지 확인하고, 댓글 · 반응을 챙기세요. 딜 사이트라면 가격이 제목과 맞는지도 봅니다.",
                      systemImage: "hand.point.right")
                    .font(.body)
                    .foregroundStyle(Color.accentColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !detection.places.isEmpty {
                VStack(spacing: 8) {
                    ForEach(detection.places) { item in
                        ReferralRow(item: item, appName: store.displayName(for: project))
                    }
                }
            }

            if !detection.passages.isEmpty {
                DisclosureGroup(isExpanded: $showsPassages) {
                    VStack(spacing: 8) {
                        ForEach(detection.passages) { item in
                            ReferralRow(item: item, appName: store.displayName(for: project))
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    Text("링크가 열린 통로 \(detection.passages.count)곳 (브라우저 · 메모 · 메일)")
                        .font(.headline)
                }
            }

            note(footnote(report))
        }
    }

    private func footnote(_ report: ReferralReport) -> String {
        var text = "App Store 상세 리포트(최근 \(report.days)일)의 출처 이름입니다. 웹은 도메인까지만, 앱은 번들 ID 로 나오고 개별 글 주소는 없어요. Safari 가 아닌 브라우저에서 누른 링크는 웹이 아니라 그 브라우저 앱으로 잡혀서 통로에 모았습니다. 프라이버시 임계값 아래의 작은 출처는 빠지므로 합계는 노출 · 전환 카드가 맞습니다. '새로'는 이 허브가 처음 본 날로부터 \(ReferralDetection.recentDays)일 안, '급증'은 최근 \(ReferralDetection.recentDays)일이 그 앞 \(ReferralDetection.recentDays)일의 \(Int(ReferralDetection.surgeRatio))배 넘게(\(ReferralDetection.surgeMinimum)건 이상) 늘어난 곳입니다."
        if report.hiddenWebDownloads > 0 {
            text += " 이름이 가려진 웹 유입이 첫 다운로드 \(AppFormat.count(report.hiddenWebDownloads))건 더 있어요."
        }
        return text
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - 한 줄

struct ReferralRow: View {
    let item: ReferralDetection.Item
    let appName: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ReferralStatusChip(status: item.status)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.profile.name)
                        .font(.headline)
                    Text(item.profile.category.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if item.profile.name != item.source.info {
                    Text(item.source.info)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let search = searchURL {
                    Link("이 사이트에서 \(appName) 찾아보기", destination: search)
                        .font(.callout)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(AppFormat.count(item.tally.firstDownloads))
                    .font(.figure(.title3))
                Text("첫 다운로드")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: 10, bordered: false)
    }

    /// 최근 셈 · 조회 · 나라 · 처음 본 날을 한 줄로.
    private var detail: String {
        var parts = ["최근 \(ReferralDetection.recentDays)일 \(AppFormat.count(item.recent))건"]
        if item.status == .surging { parts[0] += " (그 앞 \(AppFormat.count(item.previous))건)" }
        if item.tally.pageViews > 0 { parts.append("페이지 조회 \(AppFormat.count(item.tally.pageViews))") }
        let territories = item.tally.topTerritories.prefix(3)
            .map { "\(FeedbackStore.regionName($0.code)) \($0.count)" }
        if !territories.isEmpty { parts.append(territories.joined(separator: " · ")) }
        parts.append("처음 본 날 \(item.firstSeen)")
        return parts.joined(separator: " · ")
    }

    /// 웹 출처는 그 사이트 안에서 앱 이름을 찾는 검색으로. 앱 출처는 주소가 없다.
    private var searchURL: URL? {
        guard item.source.kind == .web, !item.profile.isPassage else { return nil }
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: "site:\(item.source.info) \"\(appName)\"")]
        return components?.url
    }
}

private struct ReferralStatusChip: View {
    let status: ReferralDetection.Status

    var body: some View {
        Text(status.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(status.isAlert ? Color.white : Color.secondary)
            .background(Capsule().fill(color))
            .accessibilityLabel("상태 \(status.label)")
    }

    private var color: Color {
        switch status {
        case .new: return .accentColor
        case .surging: return .orange
        case .steady: return .secondary.opacity(0.15)
        case .quiet: return .secondary.opacity(0.08)
        }
    }
}
