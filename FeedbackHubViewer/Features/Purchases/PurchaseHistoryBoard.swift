//
//  PurchaseHistoryBoard.swift
//  FeedbackHubViewer
//
//  홈의 '결제' 탭 — 결제 알림을 켠 날(2026-11-26)부터 들어온 결제 · 환불을 모든 앱에 걸쳐 날짜 순으로 쭉.
//  할 일의 '새 결제'는 본 뒤 새로 온 것만 보이니, 지난 것을 다시 보는 곳이 여기다.
//  날마다 묶고(최근 날이 위), 날 제목 옆에 그날 결제 · 환불 수. 누르면 그 앱의 결제 칸으로.
//

import SwiftUI

struct PurchaseHistoryBoard: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var keywords: KeywordStore
    @ObservedObject private var icons = StoreIcons.shared
    @State private var receipts: [PurchaseReceipt]?
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let receipts {
                let shown = receipts.filter { !store.isExcluded($0.bundleID) }
                let days = Dictionary(grouping: shown) { Calendar.current.startOfDay(for: $0.occurredAt) }
                    .sorted { $0.key > $1.key }
                Text("결제 \(shown.filter(\.isPaid).count) · 환불 \(shown.filter(\.isRefund).count)")
                    .font(.title3.weight(.semibold))
                if shown.isEmpty {
                    Text("아직 들어온 결제가 없습니다.").foregroundStyle(.secondary)
                }
                ForEach(days, id: \.key) { day, items in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(day, format: .dateTime.month().day().weekday(.abbreviated)).font(.headline)
                            Text("\(items.count)건").font(.hubCaption).foregroundStyle(.secondary)
                        }
                        ForEach(items) { row($0) }
                    }
                }
            } else if let problem {
                Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .task {
            do {
                // 알림을 켠 날부터 전부 — 레코드가 많지 않다.
                let all = try await PurchaseFeed.recent(days: 3650)
                receipts = all
                await icons.resolve(Array(Set(all.map(\.bundleID))), keywords: keywords)
            } catch {
                problem = "결제 내역을 못 읽었습니다 — \(error.localizedDescription)"
            }
        }
    }

    private func row(_ receipt: PurchaseReceipt) -> some View {
        Button {
            store.open(project: receipt.bundleID, section: .purchases)
        } label: {
            HStack(spacing: 10) {
                AppIcon(url: icons.url(for: receipt.bundleID, keywords: keywords), size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.displayName(for: receipt.bundleID)).font(.body.weight(.semibold))
                    Text(receipt.message).font(.hubCaption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if receipt.isRefund {
                    Text("환불").font(.caption.weight(.bold)).foregroundStyle(.red)
                }
                Text(AppFormat.time(receipt.occurredAt))
                    .font(.hubCaption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.03)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(store.displayName(for: receipt.bundleID)), \(receipt.isRefund ? "환불" : "결제"), \(receipt.message), \(AppFormat.time(receipt.occurredAt))")
    }
}
