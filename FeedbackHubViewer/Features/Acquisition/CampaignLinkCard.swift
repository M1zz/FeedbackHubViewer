//
//  CampaignLinkCard.swift
//  FeedbackHubViewer
//
//  글마다 몇 명이 받았나 — Apple 캠페인 링크(`pt` · `ct`)를 만들고, 상세 리포트의 Campaign 칸으로 센다.
//
//  그냥 스토어 링크로 SNS 에 올리면 그 사람들은 '웹에서' 로 한데 뭉친다. 마케팅 활동마다
//  토큰(`MarketingItem.campaignToken`)을 단 링크를 쓰면 글 하나하나가 따로 잡힌다.
//  `pt`(제공자 토큰)는 계정에 하나라 한 번만 넣는다 — iCloud 로 기기 사이에 맞춘다.
//

import SwiftUI

enum CampaignProvider {
    static let defaultsKey = "campaignProviderToken"

    static var token: String? {
        let value = UserDefaults.standard.string(forKey: defaultsKey)?.trimmingCharacters(in: .whitespaces) ?? ""
        return value.isEmpty ? nil : value
    }

    @MainActor static func set(_ token: String) {
        let digits = token.filter(\.isNumber)
        SyncedDefaults.set(digits.isEmpty ? nil : digits, forKey: defaultsKey)
    }

    /// 붙여 넣은 캠페인 링크나 숫자에서 `pt` 를 뽑는다.
    static func parse(_ text: String) -> String? {
        if let range = text.range(of: #"pt=(\d+)"#, options: .regularExpression) {
            return String(text[range].dropFirst(3))
        }
        let digits = text.filter(\.isNumber)
        return digits.count >= 4 && digits.count == text.trimmingCharacters(in: .whitespaces).count ? digits : nil
    }
}

struct CampaignLinkCard: View {
    let project: String

    @EnvironmentObject private var connect: AppStoreConnectStore
    @ObservedObject private var marketing = MarketingStore.shared
    @AppStorage(CampaignProvider.defaultsKey) private var providerToken = ""
    @State private var tokenDraft = ""
    @State private var customName = ""

    private var trackId: Int? { connect.connectApp(for: project).flatMap { Int($0.id) } }

    private var report: ReferralReport? {
        if case .ready(_, let report)? = connect.referrals[project]?.value { return report }
        return nil
    }

    var body: some View {
        Card(title: "글마다 몇 명이 받았나", systemImage: "link.badge.plus") {
            Text("SNS · 블로그에 그냥 스토어 링크를 올리면 그 사람들은 모두 '웹에서' 로 뭉칩니다. 글마다 캠페인 링크를 붙이면 글 하나하나가 몇 명을 데려왔는지 아래에 따로 나옵니다(리포트는 1~2일 늦게 옵니다).")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if providerToken.isEmpty {
                providerSetup
            } else if let trackId {
                results
                Divider()
                links(trackId: trackId)
            } else {
                Text("이 앱의 App Store 정보를 아직 못 읽었습니다.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: project) { await connect.loadReferrals(bundleID: project) }
    }

    // MARK: - pt 넣기

    private var providerSetup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("처음 한 번만: App Store Connect ▸ 앱 ▸ 분석 ▸ 획득 ▸ 캠페인 ▸ \"캠페인 링크 생성\" 에서 아무 이름으로 링크를 하나 만들어, 그 링크를 아래에 붙여 넣어 주세요. 링크 속 pt= 숫자(계정마다 하나)만 씁니다.")
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                TextField("https://apps.apple.com/app/…?pt=123456&ct=…", text: $tokenDraft)
                    .textFieldStyle(.roundedBorder)
                Button("저장") {
                    if let token = CampaignProvider.parse(tokenDraft) { CampaignProvider.set(token) }
                    tokenDraft = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(CampaignProvider.parse(tokenDraft) == nil)
            }
        }
    }

    // MARK: - 센 것

    @ViewBuilder private var results: some View {
        if let report, report.instances > 0 {
            let rows = report.campaigns.sorted { $0.value.firstDownloads > $1.value.firstDownloads }
            if rows.isEmpty {
                Text(report.hasCampaignColumn
                     ? "최근 \(report.days)일 캠페인 링크로 받은 사람이 아직 없습니다."
                     : "리포트에 캠페인 칸이 아직 없습니다.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("최근 \(report.days)일")
                        .font(.headline)
                    ForEach(rows, id: \.key) { token, tally in
                        HStack(alignment: .firstTextBaseline) {
                            Text(item(for: token).map { "\($0.channel) · \($0.title)" } ?? token)
                                .font(.body)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text("첫 다운로드 \(AppFormat.count(tally.firstDownloads))")
                                .font(.figure(.body))
                        }
                    }
                }
            }
        } else {
            Text("상세 리포트를 읽는 중이거나 아직 쌓이지 않았습니다.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private func item(for token: String) -> MarketingItem? {
        marketing.items(for: project).first { $0.campaignToken == token }
    }

    // MARK: - 링크

    private func links(trackId: Int) -> some View {
        // 아직 안 올린 마케팅 활동 — 올릴 때 이 링크를 쓴다.
        let upcoming = marketing.items(for: project)
            .filter { !$0.isDeleted && [.planned, .preparing, .ready].contains($0.stage) }
            .prefix(8)
        return VStack(alignment: .leading, spacing: 8) {
            Text("올릴 글에 붙일 링크")
                .font(.headline)
            ForEach(Array(upcoming)) { item in
                HStack(alignment: .firstTextBaseline) {
                    Text("\(item.channel) · \(item.title)")
                        .font(.body)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    CopyButton(text: MarketingCampaign.link(trackId: trackId, providerToken: providerToken,
                                                            campaignToken: item.campaignToken),
                               title: "링크 복사")
                }
            }
            HStack {
                TextField("직접 이름 짓기 (예: x-1114, reddit-launch)", text: $customName)
                    .textFieldStyle(.roundedBorder)
                CopyButton(text: MarketingCampaign.link(trackId: trackId, providerToken: providerToken,
                                                        campaignToken: Self.slug(customName)),
                           title: "링크 복사")
                    .disabled(Self.slug(customName).isEmpty)
            }
            Button("pt 다시 넣기") { CampaignProvider.set("") }
                .buttonStyle(.borderless)
                .font(.caption)
        }
    }

    /// 캠페인 토큰은 영문 · 숫자 · 하이픈만, 40자 안.
    static func slug(_ text: String) -> String {
        let mapped = text.lowercased().map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" }
        return String(String(mapped).split(separator: "-").joined(separator: "-").prefix(40))
    }
}
