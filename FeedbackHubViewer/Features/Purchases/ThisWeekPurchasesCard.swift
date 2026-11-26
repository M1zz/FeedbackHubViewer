//
//  ThisWeekPurchasesCard.swift
//  FeedbackHubViewer
//
//  "이번 주 구매" — 홈의 구매 뱃지를 누르면 맨 먼저 보이는 카드. 이번 주에 무엇이 팔렸는지를
//  세 가지 출처에서 한 번에:
//
//   · 바로 들어온 결제 — Apple 이 결제 순간 알려 준 것(`PurchaseFeed`). 상품 · 가격 · 나라 · 시각.
//   · 스토어 판매 — App Store Connect 판매 리포트, 어제까지. 날짜 · 상품 · 나라 · 수익.
//   · 앱이 센 구매 — 앱이 스스로 보낸 purchase_completed. 오늘 것까지 있지만 상품 이름이 거칠다.
//

import SwiftUI

struct ThisWeekPurchasesCard: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var purchases: AppStoreConnectStore
    let project: String
    let app: ConnectApp
    let products: [StoreProduct]

    private var receipts: [PurchaseReceipt] { purchases.receipts[project, default: []] }

    var body: some View {
        Card(title: "이번 주 구매", systemImage: "cart.fill") {
            let sales = storeSales
            let counted = appCounted
            if receipts.isEmpty && sales.isEmpty && counted.isEmpty {
                Text("최근 7일에 들어온 결제가 없습니다.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            if !receipts.isEmpty {
                section("바로 들어온 결제", note: "Apple 이 결제 순간 알려 준 것") {
                    ForEach(receipts) { receipt in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(receipt.isRefund ? "↩️" : "💰")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(receipt.message).font(.body)
                                Text(receipt.title.components(separatedBy: " · ").dropFirst().joined(separator: " · "))
                                    .font(.hubCaption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Text(AppFormat.dateTime(receipt.occurredAt))
                                .font(.hubCaption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !sales.isEmpty {
                section("스토어 판매", note: "App Store Connect 판매 리포트 · 어제까지 · 수익은 수수료 뺀 금액") {
                    ForEach(sales, id: \.self) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(ChartStorefronts.flag(row.country))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(row.product) · \(AppFormat.count(row.units))건").font(.body)
                                Text("\(ChartStorefronts.name(row.country)) · \(row.proceeds)")
                                    .font(.hubCaption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Text(row.day)
                                .font(.hubCaption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !counted.isEmpty {
                section("앱이 센 구매", note: "앱이 보낸 구매 완료 — 오늘 것까지") {
                    ForEach(counted, id: \.self) { row in
                        HStack {
                            Text(row.label).font(.body)
                            Spacer(minLength: 8)
                            Text("\(AppFormat.count(row.count))건 · \(row.day)")
                                .font(.hubCaption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let problem = purchases.receiptsProblem {
                Text("바로 들어온 결제를 읽지 못했습니다: \(problem)")
                    .font(.hubCaption)
                    .foregroundStyle(.orange)
            }
        }
        .task(id: project) { await purchases.loadReceipts() }
    }

    // MARK: - 셈

    private struct SaleRow: Hashable {
        let day: String
        let product: String
        let country: String
        let units: Int
        let proceeds: String
    }

    /// 판매 리포트를 날짜 · 상품 · 나라로 묶는다.
    private var storeSales: [SaleRow] {
        let names = Dictionary(products.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        var grouped: [String: (day: String, product: String, country: String, units: Int, proceeds: [String: Double])] = [:]
        for (day, line) in purchases.recentPurchaseLines(appleIDs: Set(products.map(\.id) + [app.id])) {
            let product = names[line.appleID] ?? line.appleID
            let key = "\(day)|\(product)|\(line.countryCode)"
            var entry = grouped[key] ?? (day, product, line.countryCode, 0, [:])
            entry.units += line.units
            entry.proceeds[line.proceedsCurrency, default: 0] += line.proceedsPerUnit * Double(line.units)
            grouped[key] = entry
        }
        return grouped.values
            .sorted { ($0.day, $0.units) > ($1.day, $1.units) }
            .map { entry in
                let money = entry.proceeds.sorted { $0.key < $1.key }
                    .map { AppStoreConnect.formatMoney($0.value, currency: $0.key) }.joined(separator: " · ")
                return SaleRow(day: String(entry.day.dropFirst(5)), product: entry.product, country: entry.country,
                               units: entry.units, proceeds: money.isEmpty ? "—" : money)
            }
    }

    private struct CountRow: Hashable {
        let day: String
        let label: String
        let count: Int
    }

    /// 앱이 보낸 purchase_completed:<무엇> 을 날짜별로.
    private var appCounted: [CountRow] {
        let days = store.days(for: project, audience: .all)
        return UsageRollups.recentDayKeys(7).reversed().flatMap { day in
            (days[day.key]?.byEvent ?? [:])
                .filter { $0.value > 0 && $0.key.hasPrefix("purchase_completed") }
                .sorted { $0.key < $1.key }
                .map { key, count in
                    let label = key.split(separator: ":").dropFirst().joined(separator: ":")
                    return CountRow(day: String(day.key.dropFirst(5)), label: label.isEmpty ? "구매" : label, count: count)
                }
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, note: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Text(note).font(.hubCaption).foregroundStyle(.secondary)
            }
            content()
        }
        .padding(.top, 4)
    }
}
