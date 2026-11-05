//
//  GiftCodePoolCard.swift
//  FeedbackHubViewer
//
//  선물 코드 묶음 현황 — 앱마다 공개 DB 에 남은 오퍼 코드, 나간 수, 이 기기의 예비. 코드 파일을 넣어 채운다.
//  앱 하나면 그 앱만, 전체면 묶음이 있는 앱을 남은 장이 적은 것부터. (`GiftCodePool`)
//

import SwiftUI
import UniformTypeIdentifiers

struct GiftCodePoolCard: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var connect: AppStoreConnectStore
    @ObservedObject private var pool = GiftCodePool.shared
    /// nil == 전체 앱.
    let project: String?
    @State private var importing = false
    @State private var imported: Int?
    @State private var fillingAll = false

    var body: some View {
        Card(title: "선물 코드 묶음", systemImage: "gift") {
            if let project {
                single(project)
            } else {
                overview
            }
        }
        .task(id: project) { await load() }
    }

    private var appKeys: [String] {
        store.projectCounts.map(\.key).filter { $0 != Feedback.unclassifiedProject && !store.hiddenProjects.contains($0) }
    }

    private func load() async {
        if let project {
            await pool.refresh(project, connect: connect)
        } else {
            for key in appKeys { await pool.refresh(key, connect: connect) }
        }
    }

    /// 모든 앱을 App Store Connect 로 100장까지.
    private func fillAll() async {
        fillingAll = true
        defer { fillingAll = false }
        for key in appKeys { await pool.fillFromStore(key, connect: connect) }
    }

    // MARK: - 앱 하나

    @ViewBuilder
    private func single(_ project: String) -> some View {
        let status = pool.statuses[project] ?? GiftPoolStatus()
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("남음 \(status.left) / \(GiftCodePool.targetSize)")
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(status.left < GiftCodePool.lowMark ? Color.red : Color.primary)
                if pool.working.contains(project) { ProgressView().controlSize(.small) }
            }
            PoolMeter(left: status.left)
            Text(detailLine(status))
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if status.left < GiftCodePool.lowMark {
                Text(status.isEmptyEverywhere
                     ? "아직 채운 적이 없습니다. 선물 판매를 켠 앱이면 코드 파일을 넣어 주세요."
                     : "곧 떨어집니다. 비면 선물을 산 사람이 링크를 기다립니다. 코드 파일을 더 넣어 주세요.")
                    .font(.body)
                    .foregroundStyle(status.isEmptyEverywhere ? Color.secondary : Color.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = pool.lastError[project] {
                Text(error)
                    .font(.body)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let imported {
                Text(imported > 0 ? "새 코드 \(imported)장을 받았습니다." : "새 코드가 없습니다. 이미 넣은 파일일 수 있습니다.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button {
                    Task { await pool.fillFromStore(project, connect: connect) }
                } label: {
                    Label("App Store Connect 로 채우기", systemImage: "bolt.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!connect.isConfigured || status.left >= GiftCodePool.targetSize)
                Button {
                    importing = true
                } label: {
                    Label("코드 파일 넣기…", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                Button {
                    Task { await pool.refresh(project, connect: connect) }
                } label: {
                    Label("새로고침", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            .disabled(pool.working.contains(project))
            Text(fillNote(project))
                .font(.hubFootnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .plainText, .text]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                pool.lastError[project] = "파일을 읽지 못했습니다."
                return
            }
            Task { imported = await pool.importCodes(from: text, bundleID: project) }
        }
    }

    private func fillNote(_ project: String) -> String {
        if !connect.isConfigured {
            return "설정에 App Store Connect 키를 넣으면 버튼 하나로 Pro 오퍼 코드를 만들어 \(GiftCodePool.targetSize)장을 채웁니다. 지금은 App Store Connect 에서 받은 코드 파일을 넣어 채울 수 있습니다."
        }
        let kind = GiftCodePool.usesSandboxCodes ? "샌드박스 코드(개발 빌드용)" : "진짜 코드"
        if pool.fillsFromStore(project) {
            return "App Store Connect 로 채우는 앱입니다. \(GiftCodePool.autoTopUpMark)장 아래로 줄면 열 때 저절로 \(GiftCodePool.targetSize)장까지 \(kind)를 다시 만듭니다. 코드는 \(AppStoreConnect.giftCodeLifetimeDays)일 뒤 끝나고, 끝나기 2주 전에 묶음에서 빠집니다."
        }
        return "App Store Connect 로 채우기를 누르면 Pro 상품에 \"\(AppStoreConnect.giftOfferName)\" 무료 오퍼 코드를 만들고 \(kind) \(GiftCodePool.targetSize)장을 iCloud 에 올립니다. 그다음부터는 줄면 저절로 채웁니다."
    }

    private func detailLine(_ status: GiftPoolStatus) -> String {
        var parts = ["나감 \(status.issued)"]
        if let last = status.lastIssuedAt { parts.append("최근 \(AppFormat.relative(last))") }
        parts.append("예비 \(status.reserve)장")
        return parts.joined(separator: " · ")
    }

    // MARK: - 전체

    @ViewBuilder
    private var overview: some View {
        let rows = appKeys
            .map { (key: $0, value: pool.statuses[$0] ?? GiftPoolStatus()) }
            .sorted { $0.value.left == $1.value.left ? store.displayName(for: $0.key) < store.displayName(for: $1.key) : $0.value.left < $1.value.left }
        let notFull = rows.filter { $0.value.left < GiftCodePool.targetSize }.count
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button {
                    Task { await fillAll() }
                } label: {
                    Label(notFull > 0 ? "전부 채우기 (\(notFull)개 앱)" : "전부 꽉 찼습니다", systemImage: "bolt.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!connect.isConfigured || fillingAll || notFull == 0)
                if fillingAll { ProgressView().controlSize(.small) }
            }
            Text(connect.isConfigured
                 ? "앱마다 Pro 비소모성 상품에 무료 오퍼 코드를 만들어 \(GiftCodePool.targetSize)장까지 채웁니다. 구독만 있는 앱은 건너뜁니다."
                 : "설정에 App Store Connect 키를 넣으면 전부 채울 수 있습니다.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            overviewRows(rows)
        }
    }

    @ViewBuilder
    private func overviewRows(_ rows: [(key: String, value: GiftPoolStatus)]) -> some View {
        if rows.isEmpty {
            Text(pool.working.isEmpty
                 ? "선물 코드 묶음이 있는 앱이 없습니다. 앱을 골라 코드 파일을 넣으면 여기 모입니다."
                 : "묶음을 읽는 중…")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(rows, id: \.key) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(store.displayName(for: entry.key))
                                .font(.body.weight(.semibold))
                            Spacer(minLength: 8)
                            Text("남음 \(entry.value.left)")
                                .font(.body.weight(.semibold).monospacedDigit())
                                .foregroundStyle(entry.value.left < GiftCodePool.lowMark ? Color.red : Color.primary)
                        }
                        PoolMeter(left: entry.value.left)
                        if rows.filter({ store.displayName(for: $0.key) == store.displayName(for: entry.key) }).count > 1 {
                            // 이름이 같은 앱이 둘이면 어느 것인지 번들 ID 로.
                            Text(entry.key)
                                .font(.body.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Text(detailLine(entry.value))
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if let error = pool.lastError[entry.key] {
                            Text(error)
                                .font(.body)
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}

/// 남은 장 막대 — 100장 기준. 적으면 빨강.
private struct PoolMeter: View {
    let left: Int

    var body: some View {
        let ratio = min(1, Double(left) / Double(GiftCodePool.targetSize))
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.15))
                Capsule()
                    .fill(left < GiftCodePool.lowMark ? Color.red : Color.green)
                    .frame(width: proxy.size.width * ratio)
            }
        }
        .frame(height: 6)
        .accessibilityLabel("남은 코드 \(left)장, \(GiftCodePool.targetSize)장 중")
    }
}
