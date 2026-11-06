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
                // 등급 선물을 파는 앱은 묶음이 등급마다 따로다(Pro · Plus).
                let keys = GiftCodePool.poolKeys(for: project)
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(keys, id: \.self) { key in
                        if keys.count > 1 {
                            Text(GiftCodePool.tierLabel(key)).font(.headline)
                        }
                        single(key)
                    }
                }
            } else {
                overview
            }
        }
        .task(id: project) { await load() }
    }

    /// 묶음 열쇠들. 앱마다 Pro 묶음과, 등급 선물을 파는 앱이면 그 등급 묶음(`GiftCodePool.tierPools`).
    private var appKeys: [String] {
        store.projectCounts.map(\.key).filter { $0 != Feedback.unclassifiedProject && !store.hiddenProjects.contains($0) }
            .flatMap(GiftCodePool.poolKeys(for:))
    }

    /// 묶음의 이름. 등급 묶음이면 앱 이름 뒤에 등급을 붙인다.
    private func name(_ key: String) -> String {
        let (bundle, product) = GiftCodePool.split(key)
        let app = store.displayName(for: bundle)
        return product == nil ? app : "\(app) · \(GiftCodePool.tierLabel(key))"
    }

    private func load() async {
        if let project {
            for key in GiftCodePool.poolKeys(for: project) { await pool.refresh(key, connect: connect) }
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
        VStack(alignment: .leading, spacing: 12) {
            GiftVerdictBanner(verdict: verdict(status, error: pool.lastError[project]),
                              working: pool.working.contains(project))
            HStack(alignment: .firstTextBaseline, spacing: 28) {
                figure("\(status.left)", "남은 코드", alarm: status.left < GiftCodePool.lowMark && !status.isEmptyEverywhere)
                figure("\(status.issued)", "선물로 나감")
                figure("\(status.reserve)", "이 맥의 예비")
                if status.refunded > 0 {
                    figure("\(status.refunded)", "환불됨", alarm: true)
                }
                if let last = status.lastIssuedAt {
                    figure(AppFormat.relative(last), "최근 나감")
                }
            }
            PoolMeter(left: status.left)
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

    /// 한 앱의 판정 — 지금 할 일이 있는가, 있으면 무엇인가.
    private func verdict(_ status: GiftPoolStatus, error: String?) -> GiftVerdict {
        if let error { return GiftVerdict(level: .warn, title: "채우지 못했습니다", detail: error) }
        if status.isEmptyEverywhere {
            return GiftVerdict(level: .idle, title: "아직 묶음이 없습니다",
                               detail: "선물을 파는 앱(선물 상품이 App Store 에 있는 앱)만 채우면 됩니다. 이 앱이 선물을 판다면 'App Store Connect 로 채우기'를 눌러 주세요.")
        }
        if status.left == 0 {
            return GiftVerdict(level: .bad, title: "코드가 다 떨어졌습니다",
                               detail: "지금 선물을 사면 받는 사람 링크가 나오지 않습니다. 바로 채워 주세요.")
        }
        if status.left < GiftCodePool.lowMark {
            return GiftVerdict(level: .bad, title: "곧 떨어집니다 · \(status.left)장 남음",
                               detail: "비면 선물을 산 사람이 링크를 기다립니다. 채워 주세요.")
        }
        return GiftVerdict(level: .good, title: "괜찮습니다 · \(status.left)장 남음",
                           detail: "할 일 없습니다. 선물이 팔리면 여기서 한 장씩 나갑니다.")
    }

    private func figure(_ value: String, _ label: String, alarm: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(alarm ? Color.red : Color.primary)
            Text(label).font(.hubFootnote).foregroundStyle(.secondary)
        }
    }

    private func detailLine(_ status: GiftPoolStatus) -> String {
        var parts = ["나감 \(status.issued)"]
        if status.refunded > 0 { parts.append("환불 \(status.refunded)") }
        if let last = status.lastIssuedAt { parts.append("최근 \(AppFormat.relative(last))") }
        parts.append("예비 \(status.reserve)장")
        return parts.joined(separator: " · ")
    }

    // MARK: - 전체

    @ViewBuilder
    private var overview: some View {
        let rows = appKeys
            .map { (key: $0, value: pool.statuses[$0] ?? GiftPoolStatus()) }
            .sorted { $0.value.left == $1.value.left ? name($0.key) < name($1.key) : $0.value.left < $1.value.left }
        let notFull = rows.filter { $0.value.left < GiftCodePool.targetSize }.count
        let active = rows.filter { !$0.value.isEmptyEverywhere }
        let low = active.filter { $0.value.left < GiftCodePool.lowMark }
        let errors = rows.filter { pool.lastError[$0.key] != nil }
        VStack(alignment: .leading, spacing: 12) {
            GiftVerdictBanner(verdict: overviewVerdict(active: active, low: low, errors: errors),
                              working: !pool.working.isEmpty || fillingAll)
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
            overviewRows(active)
            let idle = rows.count - active.count
            if idle > 0, !active.isEmpty {
                Text("묶음이 없는 앱 \(idle)개는 숨겼습니다. 선물을 팔지 않는 앱은 비어 있어도 됩니다.")
                    .font(.hubFootnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func overviewVerdict(active: [(key: String, value: GiftPoolStatus)],
                                 low: [(key: String, value: GiftPoolStatus)],
                                 errors: [(key: String, value: GiftPoolStatus)]) -> GiftVerdict {
        let names: ([(key: String, value: GiftPoolStatus)]) -> String = { list in
            list.prefix(4).map { self.name($0.key) }.joined(separator: ", ") + (list.count > 4 ? " 외 \(list.count - 4)개" : "")
        }
        if !errors.isEmpty {
            return GiftVerdict(level: .warn, title: "채우지 못한 앱 \(errors.count)개", detail: names(errors) + ". 아래에서 까닭을 확인해 주세요.")
        }
        if !low.isEmpty {
            return GiftVerdict(level: .bad, title: "채워야 할 앱 \(low.count)개", detail: names(low) + ". '전부 채우기'를 누르면 됩니다.")
        }
        if active.isEmpty {
            return GiftVerdict(level: .idle, title: "아직 묶음이 있는 앱이 없습니다",
                               detail: "선물을 파는 앱을 왼쪽에서 골라 'App Store Connect 로 채우기'를 누르면 시작됩니다.")
        }
        return GiftVerdict(level: .good, title: "모두 괜찮습니다",
                           detail: "묶음이 있는 앱 \(active.count)개 모두 \(GiftCodePool.lowMark)장 넘게 남아 있습니다. 할 일 없습니다.")
    }

    @ViewBuilder
    private func overviewRows(_ rows: [(key: String, value: GiftPoolStatus)]) -> some View {
        if rows.isEmpty {
            if !pool.working.isEmpty {
                Text("묶음을 읽는 중…")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(rows, id: \.key) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(name(entry.key))
                                .font(.body.weight(.semibold))
                            Spacer(minLength: 8)
                            Text("남음 \(entry.value.left)")
                                .font(.body.weight(.semibold).monospacedDigit())
                                .foregroundStyle(entry.value.left < GiftCodePool.lowMark ? Color.red : Color.primary)
                        }
                        PoolMeter(left: entry.value.left)
                        if rows.filter({ name($0.key) == name(entry.key) }).count > 1 {
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

/// 선물 코드 칸 맨 위의 한 줄 — 지금 할 일이 있는가.
struct GiftVerdict {
    enum Level { case good, bad, warn, idle }
    let level: Level
    let title: String
    let detail: String
}

private struct GiftVerdictBanner: View {
    let verdict: GiftVerdict
    let working: Bool

    private var color: Color {
        switch verdict.level {
        case .good: .green
        case .bad: .red
        case .warn: .orange
        case .idle: .secondary
        }
    }

    private var symbol: String {
        switch verdict.level {
        case .good: "checkmark.circle.fill"
        case .bad: "exclamationmark.circle.fill"
        case .warn: "exclamationmark.triangle.fill"
        case .idle: "circle.dashed"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(verdict.title).font(.title3.weight(.bold))
                    if working { ProgressView().controlSize(.small) }
                }
                Text(verdict.detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
}
