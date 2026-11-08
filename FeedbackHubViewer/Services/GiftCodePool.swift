//
//  GiftCodePool.swift
//  FeedbackHubViewer
//
//  앱마다 공개 DB 에 올려 두는 **App Store 오퍼 코드 묶음**(선물용)을 보고 채운다.
//
//  왜: 앱에서 Pro 선물을 사면 앱이 이 묶음에서 한 장을 가져가 App Store 사용 링크로 공유한다(LeeoKit
//  `LeeoOfferCodePool`). Pro 를 여는 것은 App Store 라 심사 3.1.1 에 걸리지 않는다. 서버가 없으니 묶음을
//  채우는 일은 개발자가 여기서 한다. 공개 DB 라 앱을 뜯는 사람은 읽을 수 있어서, 앱마다 100장만 올리고
//  나머지는 이 기기의 예비로 둔다 — 뚫려도 100장.
//
//  기록 (LeeoKit 과의 계약 — 이름을 바꾸지 않는다):
//   · `offercode-<번들>-<UUID>`        LeeoOfferCode       bundleId · code          여기서 만들고 지운다
//   · `offerclaim-<묶음 레코드 이름>`   LeeoOfferCodeClaim  transactionId · bundleId  앱이 가져간 표시
//   · `offerissue-<번들>-<결제 번호>`    LeeoOfferCodeClaim  code · transactionId · bundleId · poolRecord
//   · `offerrefund-<번들>-<결제 번호>`   LeeoOfferCodeClaim  code · transactionId · bundleId  보낸 사람이 환불받음
//
//  ⚠️ 두 타입의 `bundleId` 는 Dashboard 에서 Queryable 이어야 한다(앱도 이것으로 묶음을 찾는다).
//

import Foundation
import CloudKit

/// 한 앱의 묶음 현황.
struct GiftPoolStatus: Equatable {
    /// 공개 DB 에 남아 있는, 아직 아무도 안 가져간 장.
    var left = 0
    /// 지금까지 선물로 나간 장(발급 기록 수).
    var issued = 0
    /// 나간 장 중 보낸 사람이 환불받은 것. 코드는 되돌릴 수 없어 세기만 한다.
    var refunded = 0
    /// 가장 최근에 나간 때.
    var lastIssuedAt: Date?
    /// 이 기기에만 둔 예비 코드. 묶음이 줄면 여기서 100장까지 채운다.
    var reserve = 0
    /// 아직 한 번도 채운 적이 없다(기록이 하나도 없다).
    var isEmptyEverywhere: Bool { left == 0 && issued == 0 && reserve == 0 }
}

@MainActor
final class GiftCodePool: ObservableObject {
    static let shared = GiftCodePool()

    /// 앱마다 공개 DB 에 올려 두는 장 수. LeeoKit `LeeoOfferCodePool.targetSize` 와 같다.
    static let targetSize = 100
    /// 이보다 적게 남으면 경고한다.
    static let lowMark = 20

    /// App Store Connect 로 채운 앱은 이보다 적게 남으면 열 때 저절로 100장까지 다시 만든다.
    static let autoTopUpMark = 50
    /// 이만큼 안에 만료되는 장은 묶음에서 뺀다 — 받은 사람이 쓰기 전에 끝나지 않게.
    static let expiryMargin: TimeInterval = 14 * 86_400

    static let poolRecordType = "LeeoOfferCode"
    static let claimRecordType = "LeeoOfferCodeClaim"

    @Published private(set) var statuses: [String: GiftPoolStatus] = [:]
    @Published private(set) var working: Set<String> = []
    @Published var lastError: [String: String] = [:]

    private var database: CKDatabase {
        CKContainer(identifier: CloudKitService.containerIdentifier).publicCloudDatabase
    }

    // MARK: - 예비 (이 기기에만)

    private static func reserveKey(_ bundleID: String) -> String { "giftpool.reserve.\(bundleID)" }

    private func reserve(_ bundleID: String) -> [String] {
        UserDefaults.standard.stringArray(forKey: Self.reserveKey(bundleID)) ?? []
    }

    private func setReserve(_ codes: [String], _ bundleID: String) {
        UserDefaults.standard.set(codes, forKey: Self.reserveKey(bundleID))
        // 예비에서 빠진 코드의 만료일은 버린다.
        let kept = Set(codes)
        setExpiries(expiries(bundleID).filter { kept.contains($0.key) }, bundleID)
    }

    /// 예비 코드 → 만료일. App Store Connect 로 만든 코드만 있다(파일로 넣은 것은 모른다).
    private static func expiryKey(_ bundleID: String) -> String { "giftpool.reserveExpiry.\(bundleID)" }

    private func expiries(_ bundleID: String) -> [String: Date] {
        UserDefaults.standard.dictionary(forKey: Self.expiryKey(bundleID)) as? [String: Date] ?? [:]
    }

    private func setExpiries(_ map: [String: Date], _ bundleID: String) {
        UserDefaults.standard.set(map, forKey: Self.expiryKey(bundleID))
    }

    // MARK: - 등급 선물의 묶음

    /// 등급마다 선물을 파는 앱(LeeoKit `moreGifts`)의 둘째 묶음부터. 앱의 `LeeoGiftConfig.poolKey` 와 같아야 한다.
    /// 열쇠는 `"<번들>#<받는 상품 ID>"`, 오퍼 코드는 그 상품에 건다. 첫 묶음(Pro)은 예전처럼 번들 ID 그대로다.
    static let tierPools: [String: [(productID: String, label: String)]] = [
        "com.Ysoup.TokenMemo": [("com.Ysoup.TokenMemo.slots5", "Plus")],
        "com.xa.toki": [("com.xa.toki.remember", "Remember")],
        "com.leeo.slidesnap": [("com.leeo.slidesnap.plus", "Plus")],
        "com.example.ScheduleDensityApp": [("com.example.ScheduleDensityApp.plus", "Plus")],
        "com.burningparchment.app": [("com.burningparchment.app.plus", "Plus")],
    ]

    /// 앱 하나의 묶음 열쇠들. 첫째가 Pro(번들 ID).
    static func poolKeys(for bundleID: String) -> [String] {
        [bundleID] + (tierPools[bundleID] ?? []).map { "\(bundleID)#\($0.productID)" }
    }

    /// 열쇠를 번들 ID 와 받는 상품 ID 로. 번들 ID 만이면 상품은 nil(= Pro 를 짐작한다).
    static func split(_ key: String) -> (bundleID: String, productID: String?) {
        guard let mark = key.firstIndex(of: "#") else { return (key, nil) }
        return (String(key[..<mark]), String(key[key.index(after: mark)...]))
    }

    /// 화면에 적는 등급 이름. 첫 묶음은 "Pro".
    static func tierLabel(_ key: String) -> String {
        let (bundle, product) = split(key)
        guard let product else { return "Pro" }
        return tierPools[bundle]?.first { $0.productID == product }?.label ?? product
    }

    // MARK: - App Store Connect 로 채우기

    private static func storeFillKey(_ bundleID: String) -> String { "giftpool.ascfill.\(bundleID)" }

    /// 한 번 App Store Connect 로 채운 앱 — 열 때마다 저절로 다시 채운다.
    func fillsFromStore(_ bundleID: String) -> Bool {
        UserDefaults.standard.bool(forKey: Self.storeFillKey(bundleID))
    }

    /// CloudKit 개발 환경을 보는 빌드면 샌드박스 코드, 운영 환경이면 진짜 코드 — 묶음을 읽는 앱이
    /// 같은 환경의 App Store 를 보도록. (Debug-Production 으로 Xcode 에서 돌려도 운영이다.)
    static var usesSandboxCodes: Bool {
        #if CLOUDKIT_PRODUCTION
        return false
        #else
        return true
        #endif
    }

    /// App Store Connect 에서 오퍼 코드를 만들어 100장까지 채운다. 다음부터는 열 때 저절로.
    func fillFromStore(_ bundleID: String, connect: AppStoreConnectStore) async {
        // 화면이 열리며 돈 새로고침이 끝나기를 기다린다 — 그냥 돌아서면 단추가 말없이 안 먹는다.
        while working.contains(bundleID) { try? await Task.sleep(nanoseconds: 200_000_000) }
        working.insert(bundleID)
        defer { working.remove(bundleID) }
        do {
            try await sync(bundleID)
            try await topUpFromStore(bundleID, connect: connect, below: Self.targetSize)
            UserDefaults.standard.set(true, forKey: Self.storeFillKey(bundleID))
            lastError[bundleID] = nil
        } catch {
            lastError[bundleID] = Self.describe(error)
            print("❌ [GiftCodePool.fillFromStore] \(bundleID): \(error)")
        }
    }

    private func topUpFromStore(_ bundleID: String, connect: AppStoreConnectStore, below mark: Int) async throws {
        let left = statuses[bundleID]?.left ?? 0
        guard left < mark else { return }
        guard let client = connect.client else { throw AppStoreConnect.Failure.missing("App Store Connect 키") }
        let (appBundle, product) = Self.split(bundleID)
        let app = try await connect.resolveApp(appBundle)
        // 이미 예비에 있는 만큼은 새로 만들지 않는다. Apple 은 500장 단위로만 만들어서, 남는 장은
        // 예비로 두었다가 묶음이 줄면 채운다.
        let need = Self.targetSize - left - reserve(bundleID).count
        if need > 0 {
            let batch = try await client.makeGiftCodes(appID: app.id, bundleID: appBundle, count: need,
                                                       sandbox: Self.usesSandboxCodes, productID: product)
            // 먼저 예비에 둔다 — iCloud 에 올리다 실패해도 만든 코드를 잃지 않는다.
            setReserve(reserve(bundleID) + batch.codes, bundleID)
            var map = expiries(bundleID)
            for code in batch.codes { map[code] = batch.expires }
            setExpiries(map, bundleID)
        }
        try await sync(bundleID)
    }

    // MARK: - 보기

    /// 묶음을 읽고, 가져간 장을 지우고, 예비로 100장까지 채운다.
    /// `connect` 를 주면, App Store Connect 로 채운 적 있는 앱은 50장 아래일 때 100장까지 다시 만든다.
    func refresh(_ bundleID: String, connect: AppStoreConnectStore? = nil) async {
        guard !working.contains(bundleID) else { return }
        working.insert(bundleID)
        defer { working.remove(bundleID) }
        do {
            try await sync(bundleID)
            if let connect, fillsFromStore(bundleID) {
                try await topUpFromStore(bundleID, connect: connect, below: Self.autoTopUpMark)
            }
            lastError[bundleID] = nil
        } catch {
            lastError[bundleID] = Self.describe(error)
            print("❌ [GiftCodePool.refresh] \(bundleID): \(error)")
        }
    }

    /// App Store Connect 에서 받은 코드 파일을 넣는다. 이미 아는 코드는 버리고 예비에 더한 뒤 채운다.
    /// 돌려주는 값은 새로 받은 코드 수.
    @discardableResult
    func importCodes(from text: String, bundleID: String) async -> Int {
        let parsed = Self.parseCodes(text)
        guard !working.contains(bundleID) else { return 0 }
        working.insert(bundleID)
        defer { working.remove(bundleID) }
        do {
            let known = try await knownCodes(bundleID).union(reserve(bundleID))
            let fresh = parsed.filter { !known.contains($0) }
            setReserve(reserve(bundleID) + fresh, bundleID)
            try await sync(bundleID)
            lastError[bundleID] = parsed.isEmpty ? "파일에서 코드를 찾지 못했습니다. App Store Connect 에서 받은 일회용 코드 파일인지 확인하세요." : nil
            return fresh.count
        } catch {
            lastError[bundleID] = Self.describe(error)
            return 0
        }
    }

    // MARK: - 안쪽

    private func sync(_ bundleID: String) async throws {
        let pool = try await query(Self.poolRecordType, bundleID: bundleID)
        let claims = try await query(Self.claimRecordType, bundleID: bundleID)
        let claimNames = Set(claims.map(\.recordID.recordName))
        let issues = claims.filter { $0.recordID.recordName.hasPrefix("offerissue-") }
        let refunds = claims.filter { $0.recordID.recordName.hasPrefix("offerrefund-") }

        // 가져간 장은 지운다 — 남은 장만 묶음에 두어야 앱이 빨리 찾는다.
        // 곧 만료되는 장도 — 받은 사람 손에서 끝나면 안 된다.
        let soon = Date().addingTimeInterval(Self.expiryMargin)
        let taken = pool.filter {
            claimNames.contains("offerclaim-\($0.recordID.recordName)")
                || (($0["expiresAt"] as? Date).map { $0 < soon } ?? false)
        }
        if !taken.isEmpty {
            _ = try await database.modifyRecords(saving: [], deleting: taken.map(\.recordID))
        }
        var left = pool.count - taken.count

        // 예비로 100장까지. 곧 끝나는 예비 코드는 버린다.
        let spareExpiry = expiries(bundleID)
        var spare = reserve(bundleID).filter { spareExpiry[$0].map { $0 >= soon } ?? true }
        if spare.count != reserve(bundleID).count { setReserve(spare, bundleID) }
        let need = max(0, Self.targetSize - left)
        if need > 0, !spare.isEmpty {
            let batch = Array(spare.prefix(need))
            try await upload(batch, bundleID: bundleID)
            spare.removeFirst(batch.count)
            setReserve(spare, bundleID)
            left += batch.count
        }

        statuses[bundleID] = GiftPoolStatus(
            left: left,
            issued: issues.count,
            refunded: refunds.count,
            lastIssuedAt: issues.compactMap(\.creationDate).max(),
            reserve: spare.count)
    }

    private func upload(_ codes: [String], bundleID: String) async throws {
        let expiry = expiries(bundleID)
        let records = codes.map { code -> CKRecord in
            let record = CKRecord(recordType: Self.poolRecordType,
                                  recordID: CKRecord.ID(recordName: "offercode-\(bundleID)-\(UUID().uuidString)"))
            record["bundleId"] = bundleID
            record["code"] = code
            if let expires = expiry[code] { record["expiresAt"] = expires }
            return record
        }
        for chunk in stride(from: 0, to: records.count, by: 200).map({ Array(records[$0..<min($0 + 200, records.count)]) }) {
            _ = try await database.modifyRecords(saving: chunk, deleting: [])
        }
    }

    /// 묶음 · 나간 것에 이미 있는 코드. 같은 파일을 두 번 넣어도 겹치지 않게.
    private func knownCodes(_ bundleID: String) async throws -> Set<String> {
        let pool = try await query(Self.poolRecordType, bundleID: bundleID)
        let claims = try await query(Self.claimRecordType, bundleID: bundleID)
        return Set((pool + claims).compactMap { $0["code"] as? String })
    }

    private func query(_ type: String, bundleID: String) async throws -> [CKRecord] {
        let query = CKQuery(recordType: type, predicate: NSPredicate(format: "bundleId == %@", bundleID))
        var records: [CKRecord] = []
        let first: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
        do {
            first = try await database.records(matching: query, resultsLimit: 200)
        } catch let error as CKError where error.code == .unknownItem {
            // 타입이 아직 없다 — 처음 채우기 전이거나 아직 아무도 안 샀다. 빈 것으로 보고 이어 간다
            // (처음 올리면 개발 환경에 타입이 생긴다. 그다음 Dashboard 에서 bundleId 를 Queryable 로).
            return []
        }
        var (matches, cursor) = first
        records += matches.compactMap { try? $0.1.get() }
        while let next = cursor {
            (matches, cursor) = try await database.records(continuingMatchFrom: next, resultsLimit: 200)
            records += matches.compactMap { try? $0.1.get() }
        }
        return records
    }

    private static func describe(_ error: Error) -> String {
        if let ck = error as? CKError {
            switch ck.code {
            case .unknownItem:
                // 타입이 아직 없다 — 한 번도 채운 적이 없는 컨테이너.
                return "아직 묶음이 없습니다. 코드 파일을 넣으면 만들어집니다."
            case .invalidArguments, .serverRejectedRequest, .partialFailure:
                let raw = (ck.partialErrorsByItemID?.values.first as? CKError)?.localizedDescription
                    ?? (ck.userInfo[NSLocalizedDescriptionKey] as? String) ?? ck.localizedDescription
                if raw.localizedCaseInsensitiveContains("production schema") || raw.localizedCaseInsensitiveContains("create new type") {
                    return "운영 CloudKit 에 LeeoOfferCode · LeeoOfferCodeClaim 타입이 아직 없습니다. 개발 환경에 만든 뒤 Production 으로 배포해야 합니다. 만든 코드는 예비에 두었습니다. (\(raw))"
                }
                if raw.localizedCaseInsensitiveContains("queryable") {
                    return "CloudKit Dashboard 에서 LeeoOfferCode · LeeoOfferCodeClaim 의 bundleId 를 Queryable 로 해 주세요. (\(raw))"
                }
                return raw
            case .notAuthenticated:
                return "이 기기가 iCloud 에 로그인되어 있지 않습니다."
            default:
                return ck.localizedDescription
            }
        }
        return error.localizedDescription
    }

    /// App Store Connect 의 일회용 코드 파일(CSV · 텍스트)에서 코드만. 영문과 숫자가 섞인 6~64자.
    /// 머리줄 · 날짜 · 상품 ID · 겹친 것은 버린다. LeeoKit `LeeoOfferCodePool.parseCodes` 와 같은 규칙.
    nonisolated static func parseCodes(_ text: String) -> [String] {
        var seen = Set<String>()
        var codes: [String] = []
        for line in text.components(separatedBy: .newlines) {
            for cell in line.components(separatedBy: CharacterSet(charactersIn: ",;\t ")) {
                let value = cell.trimmingCharacters(in: CharacterSet(charactersIn: "\"' ")).uppercased()
                guard value.count >= 6, value.count <= 64,
                      value.unicodeScalars.allSatisfy({ $0.isASCII && CharacterSet.alphanumerics.contains($0) }),
                      value.contains(where: \.isNumber), value.contains(where: \.isLetter),
                      seen.insert(value).inserted else { continue }
                codes.append(value)
            }
        }
        return codes
    }
}
