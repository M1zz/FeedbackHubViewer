//
//  PurchaseFeed.swift
//  FeedbackHubViewer
//
//  결제 서버(app-portfolio `services/purchase-notify`)가 남긴 `Purchase` 를 읽는다.
//  Apple 이 결제 순간 알려 준 것이라 판매 리포트(하루 늦음)보다 빠르고, 상품 · 가격 · 나라 · 시각이 다 있다.
//  결제 알림을 켠 날(2026-11-26)부터 쌓인다.
//

import CloudKit

struct PurchaseReceipt: Identifiable, Hashable {
    let id: String
    let bundleID: String
    let title: String
    let message: String
    let kind: String
    let productID: String
    let occurredAt: Date
    let isSandbox: Bool
    /// 고객이 낸 금액 × 1000(Apple 의 단위). 0 이면 코드로 받은 것 — 결제가 아니다.
    let priceMilli: Int64

    var isRefund: Bool { kind == "REFUND" }
    /// 돈이 실제로 들어온 결제.
    var isPaid: Bool { !isRefund && priceMilli > 0 }
}

enum PurchaseFeed {
    /// 최근 `days` 일의 결제 · 환불(시험 · 샌드박스 · 0원 코드 빼고), 모든 앱, 최근 것부터.
    /// 레코드가 많지 않아 다 받아 앱에서 거른다 — 인덱스는 recordName 하나면 된다.
    static func recent(days: Int = 7) async throws -> [PurchaseReceipt] {
        let database = CKContainer(identifier: CloudKitService.containerIdentifier).publicCloudDatabase
        let query = CKQuery(recordType: PushSubscriptions.purchaseRecordType, predicate: NSPredicate(value: true))
        let since = Date().addingTimeInterval(-Double(days) * 86_400)
        var receipts: [PurchaseReceipt] = []
        var cursor: CKQueryOperation.Cursor?
        repeat {
            let page = if let cursor {
                try await database.records(continuingMatchFrom: cursor)
            } else {
                try await database.records(matching: query, resultsLimit: 200)
            }
            for (_, result) in page.matchResults {
                guard let record = try? result.get() else { continue }
                let receipt = PurchaseReceipt(
                    id: record.recordID.recordName,
                    bundleID: record["bundleID"] as? String ?? "",
                    title: record["title"] as? String ?? "",
                    message: record["message"] as? String ?? "",
                    kind: record["kind"] as? String ?? "",
                    productID: record["productID"] as? String ?? "",
                    occurredAt: Date(timeIntervalSince1970: Double(record["occurredAt"] as? Int64 ?? 0) / 1000),
                    isSandbox: (record["sandbox"] as? Int64 ?? 0) == 1,
                    priceMilli: record["priceMilli"] as? Int64 ?? 0)
                if receipt.isPaid || receipt.isRefund, !receipt.isSandbox, receipt.occurredAt >= since {
                    receipts.append(receipt)
                }
            }
            cursor = page.queryCursor
        } while cursor != nil
        return receipts.sorted { $0.occurredAt > $1.occurredAt }
    }
}
