//
//  InAppPurchasesView.swift
//  FeedbackHubViewer
//
//  "앱 내 구입" 섹션 — App Store Connect에 걸린 상품과 최근 30일 판매.
//
//  통계 섹션의 "산 것" 카드는 앱이 스스로 보낸 값(own.*)이고, 여기는 스토어가 말하는
//  값이다. 둘을 나란히 볼 수 있어야 앱이 보낸 값을 믿을지 말지가 정해진다.
//
//  전체 프로젝트에서는 합이 아니라 앱끼리의 순위다(`ProjectComparisonView`와 같은 까닭).
//  지금은 읽기만 한다 — 가격 변경·상품 생성은 실수하면 곧장 스토어에 나간다.
//

import SwiftUI
import UniformTypeIdentifiers

struct InAppPurchasesView: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var purchases: InAppPurchaseStore
    /// nil == 전체 프로젝트.
    let project: String?

    @State private var isEditingKey = false

    #if os(macOS)
    private let tileColumns = [GridItem(.adaptive(minimum: 180), spacing: 10)]
    private let contentPadding: CGFloat = 16
    #else
    private let tileColumns = [GridItem(.flexible(), spacing: 10),
                               GridItem(.flexible(), spacing: 10)]
    private let contentPadding: CGFloat = 12
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !purchases.isConfigured {
                    Card(title: "App Store Connect 연결", systemImage: "key") {
                        ConnectKeyForm(onSaved: {})
                    }
                } else {
                    header
                    if let project {
                        ProjectPurchases(project: project, tileColumns: tileColumns)
                    } else {
                        PurchaseComparison()
                    }
                }
            }
            .padding(contentPadding)
        }
        .sheet(isPresented: $isEditingKey) {
            NavigationStack {
                ScrollView {
                    ConnectKeyForm(onSaved: { isEditingKey = false })
                        .padding()
                }
                .navigationTitle("App Store Connect 키")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("닫기") { isEditingKey = false }
                    }
                }
            }
            #if os(macOS)
            .frame(minWidth: 520, minHeight: 520)
            #endif
        }
        .task(id: project) {
            guard purchases.isConfigured else { return }
            if let project {
                await purchases.loadCatalog(bundleID: project)
            }
            await purchases.loadSales()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("App Store Connect에서 읽은 값입니다. 판매는 최근 \(InAppPurchaseStore.salesDays)일(어제까지, 태평양 시간 기준)이에요.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button {
                Task {
                    if let project { await purchases.loadCatalog(bundleID: project, force: true) }
                    await purchases.loadSales(force: true)
                }
            } label: {
                Label("다시 읽기", systemImage: "arrow.clockwise")
            }
            Button {
                isEditingKey = true
            } label: {
                Label("키 설정", systemImage: "key")
            }
        }
        .font(.body)
    }
}

// MARK: - 한 앱

private struct ProjectPurchases: View {
    @EnvironmentObject private var purchases: InAppPurchaseStore
    let project: String
    let tileColumns: [GridItem]

    var body: some View {
        switch purchases.catalogs[project] {
        case nil, .loading?:
            ProgressView("상품을 읽는 중…")
                .font(.body)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        case .failed(let message)?:
            Card(title: "상품을 읽지 못했습니다", systemImage: "exclamationmark.triangle") {
                Text(message)
                    .font(.body)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .loaded(let app, let products)?:
            summary(app, products)
            productsCard(products)
            SalesStatus()
        }
    }

    private func summary(_ app: ConnectApp, _ products: [StoreProduct]) -> some View {
        let totals = purchases.sales?.totals(app: app, products: products)
        return VStack(alignment: .leading, spacing: 10) {
        LazyVGrid(columns: tileColumns, spacing: 10) {
            StatTile(title: "판매 중인 상품", value: "\(products.filter(\.isOnSale).count)",
                     unit: "/ \(products.count)개", systemImage: "bag", tint: .accentColor)
            StatTile(title: "최근 30일 유료 결제", value: totals.map { "\($0.purchases)" } ?? "—",
                     unit: "건", systemImage: "creditcard", tint: .green)
            StatTile(title: "최근 30일 코드로 0원", value: totals.map { "\($0.freeRedemptions)" } ?? "—",
                     unit: "건", systemImage: "gift", tint: .pink)
            StatTile(title: "최근 30일 수익금", value: totals?.proceedsLabel ?? "—",
                     systemImage: "wonsign.circle", tint: .orange)
            StatTile(title: "최근 30일 첫 다운로드", value: totals.map { "\($0.firstDownloads)" } ?? "—",
                     unit: "회", systemImage: "arrow.down.circle", tint: .blue)
        }
        if let totals, totals.freeRedemptions > 0 {
            // 0원 코드가 돈 낸 결제보다 많으면 그게 이 앱의 가장 큰 사실이다 —
            // 유료기능이 열린 사람 대부분이 여기서 왔다는 뜻이라, 타일 밑에 말로 적는다.
            Label("0원으로 받은 \(totals.freeRedemptions)건은 오퍼 · 프로모션 코드입니다 — \(totals.codesLabel). 유료 결제 \(totals.purchases)건과 따로 셉니다.",
                  systemImage: "gift")
                .font(.body)
                .foregroundStyle(totals.freeRedemptions > totals.purchases ? AnyShapeStyle(.pink) : AnyShapeStyle(.secondary))
                .fixedSize(horizontal: false, vertical: true)
        }
        }
    }

    private func productsCard(_ products: [StoreProduct]) -> some View {
        Card(title: "상품", systemImage: "bag") {
            if products.isEmpty {
                Text("이 앱에는 인앱 상품도 구독도 없습니다.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(products.enumerated()), id: \.element.id) { index, product in
                        productRow(product)
                        if index < products.count - 1 { Divider() }
                    }
                }
                Text("결제는 고객이 돈을 낸 것만 셉니다. 오퍼 · 프로모션 코드로 0원에 받은 것은 \"코드\"로 따로 적어요. 수익금은 Apple 수수료와 세금을 뺀 개발자 몫이고, 통화별로 따로 더합니다. 환불은 음수로 들어와 건수에서 빠져요.")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func productRow(_ product: StoreProduct) -> some View {
        let sold = purchases.sales?.totals(for: product.id)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(product.name)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Tag(text: product.stateLabel, tint: product.isOnSale ? .green : .orange, font: .body)
                Spacer(minLength: 8)
                Text(product.price ?? "가격 모름")
                    .font(.body.monospacedDigit().weight(.semibold))
                    .foregroundStyle(product.price == nil ? .secondary : .primary)
            }
            Text(product.productID)
                .font(.body.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            HStack(spacing: 8) {
                Text([product.kind.label, product.groupName, product.periodLabel]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.body)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if let sold {
                    Text("30일 결제 \(sold.purchases)건" + (sold.freeRedemptions != 0 ? " · 코드 \(sold.freeRedemptions)건" : "") + " · \(sold.proceedsLabel)")
                        .font(.body.monospacedDigit())
                        .foregroundStyle(sold.units > 0 ? .primary : .secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

// MARK: - 전체 프로젝트

/// 앱끼리의 순위. 번들 ID로 App Store Connect 앱을 하나씩 찾아서, 그 앱과 상품들의
/// 판매를 붙인다. App Store Connect에 없는 프로젝트(개발 중·다른 계정)는 줄에서 빠진다.
private struct PurchaseComparison: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var purchases: InAppPurchaseStore

    private var keys: [String] {
        store.allProjectKeys.filter { $0 != Feedback.unclassifiedProject }
    }

    private struct Row: Identifiable {
        let id: String
        let name: String
        let totals: InAppPurchaseStore.SalesWindow.Totals
        let onSale: Int
    }

    var body: some View {
        let rows = self.rows
        let pending = keys.filter {
            if case .loading? = purchases.catalogs[$0] { return true }
            return purchases.catalogs[$0] == nil
        }.count

        Group {
            if pending > 0 {
                ProgressView("앱 \(keys.count)개 중 \(keys.count - pending)개 읽음…")
                    .font(.body)
                    .frame(maxWidth: .infinity)
            }
            SalesStatus()
            if let sales = purchases.sales {
                ranking(rows, title: "인앱 결제가 많은 앱", systemImage: "creditcard") {
                    $0.totals.purchases > 0 ? ("\($0.totals.purchases)건", Double($0.totals.purchases), $0.totals.proceedsLabel) : nil
                }
                ranking(rows, title: "코드로 0원에 받은 건이 많은 앱", systemImage: "gift") {
                    $0.totals.freeRedemptions > 0 ? ("\($0.totals.freeRedemptions)건", Double($0.totals.freeRedemptions), $0.totals.codesLabel) : nil
                }
                ranking(rows, title: "첫 다운로드가 많은 앱", systemImage: "arrow.down.circle") {
                    $0.totals.firstDownloads > 0 ? ("\($0.totals.firstDownloads)회", Double($0.totals.firstDownloads), "판매 중인 상품 \($0.onSale)개") : nil
                }
                if sales.missingDays > 0 {
                    Text("\(sales.days)일 중 \(sales.missingDays)일은 리포트를 못 받아 빠졌습니다.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            let skipped = keys.filter { if case .failed? = purchases.catalogs[$0] { return true }; return false }
            if !skipped.isEmpty {
                Card(title: "App Store Connect에서 못 찾은 프로젝트", systemImage: "questionmark.circle") {
                    Text(skipped.map { store.displayName(for: $0) }.joined(separator: ", "))
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("번들 ID로 찾았는데 없거나, 읽다가 실패한 프로젝트입니다. 스토어에 아직 안 낸 앱이면 정상이에요. 프로젝트 하나를 열면 이유가 나옵니다.")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .task {
            // 앱마다 차례로. 한꺼번에 쏘면 App Store Connect의 시간당 한도를 금방 쓴다.
            for key in keys { await purchases.loadCatalog(bundleID: key) }
        }
    }

    private var rows: [Row] {
        guard let sales = purchases.sales else { return [] }
        return keys.compactMap { key in
            guard let app = purchases.connectApp(for: key),
                  let products = purchases.products(for: key) else { return nil }
            return Row(id: key, name: store.displayName(for: key),
                       totals: sales.totals(app: app, products: products),
                       onSale: products.filter(\.isOnSale).count)
        }
    }

    private func ranking(_ rows: [Row], title: String, systemImage: String,
                         metric: (Row) -> (text: String, value: Double, hint: String)?) -> some View {
        let ranked = rows.compactMap { row in metric(row).map { (row, $0) } }
            .sorted { $0.1.value > $1.1.value }
        let peak = ranked.first?.1.value ?? 0
        return Card(title: title, systemImage: systemImage) {
            if ranked.isEmpty {
                Text("최근 \(InAppPurchaseStore.salesDays)일에 해당하는 앱이 없습니다.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(ranked.enumerated()), id: \.element.0.id) { index, entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(index + 1)")
                                    .font(.body.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(index == 0 ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                                    .frame(minWidth: 22, alignment: .trailing)
                                Text(entry.0.name)
                                    .font(.body.weight(index == 0 ? .semibold : .regular))
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text(entry.1.text)
                                    .font(.body.monospacedDigit().weight(.semibold))
                            }
                            MeterBar(ratio: peak > 0 ? entry.1.value / peak : 0)
                                .padding(.leading, 30)
                            Text(entry.1.hint)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 30)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 판매 리포트 상태

/// 판매 리포트를 왜 못 보여 주는지 — 판매자 번호가 없거나, 받는 중이거나, 거절당했거나.
private struct SalesStatus: View {
    @EnvironmentObject private var purchases: InAppPurchaseStore

    var body: some View {
        if purchases.credentials?.hasVendorNumber != true {
            Card(title: "판매 리포트", systemImage: "chart.bar.doc.horizontal") {
                Text("판매자 번호를 넣으면 최근 30일 결제 건수와 수익금이 나옵니다. App Store Connect의 \"판매 및 추세\" 화면 왼쪽 위에 있는 숫자예요. 오른쪽 위 \"키 설정\"에서 넣을 수 있습니다.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if let error = purchases.salesError {
            Card(title: "판매 리포트를 못 읽었습니다", systemImage: "exclamationmark.triangle") {
                Text(error)
                    .font(.body)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Text("판매 리포트는 키 역할이 Admin · Finance · Sales 중 하나여야 읽힙니다.")
                    .font(.body)
                    .foregroundStyle(.tertiary)
            }
        } else if purchases.isLoadingSales {
            ProgressView("최근 \(InAppPurchaseStore.salesDays)일 판매 리포트를 받는 중…")
                .font(.body)
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - 키 입력

private struct ConnectKeyForm: View {
    @EnvironmentObject private var purchases: InAppPurchaseStore
    let onSaved: () -> Void

    @State private var issuerID = ""
    @State private var keyID = ""
    @State private var privateKey = ""
    @State private var vendorNumber = ""
    @State private var error: String?
    @State private var isImporting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("App Store Connect → 사용자 및 액세스 → 통합 → App Store Connect API에서 팀 키를 만들고, 아래 세 값을 넣어 주세요. 키는 이 기기의 키체인에만 저장됩니다.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            field("Issuer ID", text: $issuerID, prompt: "57246542-96fe-1a63-e053-0824d011072a")
            field("Key ID", text: $keyID, prompt: "2X9R4HXF34")

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("개인 키 (.p8)").font(.headline)
                    Spacer()
                    Button("파일에서 불러오기") { isImporting = true }
                        .font(.body)
                }
                TextEditor(text: $privateKey)
                    .font(.body.monospaced())
                    .frame(minHeight: 110)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
                Text("키는 만들 때 한 번만 내려받을 수 있습니다. 잃어버렸으면 새로 만들어야 해요.")
                    .font(.body)
                    .foregroundStyle(.tertiary)
            }

            field("판매자 번호 (선택)", text: $vendorNumber, prompt: "8xxxxxxx")
            Text("판매 리포트용입니다. \"판매 및 추세\" 화면 왼쪽 위에 있어요. 판매 리포트까지 읽으려면 키 역할이 Admin 또는 Finance여야 합니다.")
                .font(.body)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            if let error {
                Text(error)
                    .font(.body)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("저장") { save() }
                    .buttonStyle(.borderedProminent)
                if purchases.isConfigured {
                    Button("키 지우기", role: .destructive) {
                        purchases.signOut()
                        onSaved()
                    }
                }
            }
            .font(.body)
        }
        .onAppear {
            guard let saved = purchases.credentials else { return }
            issuerID = saved.issuerID
            keyID = saved.keyID
            privateKey = saved.privateKey
            vendorNumber = saved.vendorNumber ?? ""
        }
        .fileImporter(isPresented: $isImporting,
                      allowedContentTypes: [UTType(filenameExtension: "p8") ?? .data, .data]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                privateKey = text
                // AuthKey_2X9R4HXF34.p8 — 파일 이름에 Key ID가 들어 있다.
                let name = url.deletingPathExtension().lastPathComponent
                if keyID.isEmpty, name.hasPrefix("AuthKey_") {
                    keyID = String(name.dropFirst("AuthKey_".count))
                }
            } else {
                error = "파일을 읽지 못했습니다."
            }
        }
    }

    private func field(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            TextField(title, text: text, prompt: Text(prompt))
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
        }
    }

    private func save() {
        let vendor = vendorNumber.trimmingCharacters(in: .whitespaces)
        let credentials = AppStoreConnectCredentials(
            issuerID: issuerID.trimmingCharacters(in: .whitespaces),
            keyID: keyID.trimmingCharacters(in: .whitespaces),
            privateKey: privateKey,
            vendorNumber: vendor.isEmpty ? nil : vendor)
        do {
            try purchases.save(credentials)
            error = nil
            onSaved()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
