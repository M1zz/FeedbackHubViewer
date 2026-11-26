//
//  PushSubscriptions.swift
//  FeedbackHubViewer
//
//  새 피드백 · 진단이 허브에 들어오면 Apple 이 이 기기로 바로 알림을 보내게 하는 CloudKit
//  구독. 앱이 꺼져 있어도 맥 · 아이폰에 뜬다 - 로컬 알림(`NotificationService`)은 앱이
//  돌고 있어야 하지만 이것은 아니다.
//
//  구독은 공개 데이터베이스에 이 iCloud 사용자 몫으로 저장되고, 알림은 구독을 저장한
//  기기들로 간다. 그래서 기기마다 한 번씩 저장한다. 같은 id 로 다시 저장하면 덮어쓸 뿐이다.
//

import CloudKit

enum PushSubscriptions {

    private static var database: CKDatabase {
        CKContainer(identifier: CloudKitService.containerIdentifier).publicCloudDatabase
    }

    private static func subscriptionID(_ kind: AttentionKind) -> String { "hub-new-\(kind.rawValue)" }

    /// 푸시로 받을 수 있는 종류. 리뷰는 App Store Connect 에 있어서 CloudKit 이 모른다.
    static let pushable: [AttentionKind] = [.feedback, .crash]

    /// `kinds` 만 구독이 걸려 있게 맞춘다. 걸린 종류를 돌려준다 - 실패한 것은 빠진다.
    static func sync(_ kinds: Set<AttentionKind>, feedbackRecordType: String) async -> Set<AttentionKind> {
        var active: Set<AttentionKind> = []
        for kind in pushable {
            let id = subscriptionID(kind)
            if kinds.contains(kind) {
                let recordType = kind == .feedback ? feedbackRecordType : CloudKitService.crashRecordType
                let subscription = CKQuerySubscription(recordType: recordType,
                                                       predicate: NSPredicate(value: true),
                                                       subscriptionID: id,
                                                       options: [.firesOnRecordCreation])
                let info = CKSubscription.NotificationInfo()
                info.title = kind == .feedback ? "새 피드백" : "새 진단"
                info.alertBody = kind == .feedback
                    ? "허브에 새 피드백이 도착했습니다"
                    : "크래시·멈춤 리포트가 올라왔습니다"
                info.soundName = "default"
                // 앱이 돌고 있으면 깨워서 목록을 바로 새로 읽게 한다.
                info.shouldSendContentAvailable = true
                subscription.notificationInfo = info
                do {
                    _ = try await database.save(subscription)
                    active.insert(kind)
                } catch {
                    print("❌ [PushSubscriptions.sync] \(kind.rawValue): \(error)")
                }
            } else {
                do {
                    _ = try await database.deleteSubscription(withID: id)
                } catch let error as CKError where error.code == .unknownItem {
                    // 처음부터 없었다.
                } catch {
                    print("❌ [PushSubscriptions.sync] delete \(kind.rawValue): \(error)")
                }
            }
        }
        return active
    }

    /// 결제 알림. Apple 이 결제를 알리면 서버(`app-portfolio/services/purchase-notify`)가
    /// `Purchase` 를 남기고, 이 구독이 그 제목 · 내용을 그대로 띄운다 — 문구는 서버가 만든다.
    /// 알림을 켜 두면 늘 건다. 결제는 놓치고 싶은 사람이 없다.
    static let purchaseRecordType = "Purchase"
    static let purchaseSubscriptionID = "hub-new-purchase"

    /// 걸었으면 nil, 못 걸었으면 그 까닭. 끄면 늘 nil.
    static func syncPurchases(_ enabled: Bool) async -> String? {
        do {
            if enabled {
                let subscription = CKQuerySubscription(recordType: purchaseRecordType,
                                                       predicate: NSPredicate(value: true),
                                                       subscriptionID: purchaseSubscriptionID,
                                                       options: [.firesOnRecordCreation])
                let info = CKSubscription.NotificationInfo()
                // 레코드 칸을 그대로 쓰려면 지역화 키를 거쳐야 한다. 키 "%1$@" 는 Localizable.strings 에 있다.
                info.titleLocalizationKey = "%1$@"
                info.titleLocalizationArgs = ["title"]
                info.alertLocalizationKey = "%1$@"
                info.alertLocalizationArgs = ["message"]
                info.soundName = "default"
                subscription.notificationInfo = info
                _ = try await database.save(subscription)
            } else {
                _ = try await database.deleteSubscription(withID: purchaseSubscriptionID)
            }
            return nil
        } catch let error as CKError where error.code == .unknownItem && !enabled {
            return nil // 지울 구독이 처음부터 없었다.
        } catch {
            print("❌ [PushSubscriptions.syncPurchases] \(error)")
            return error.localizedDescription
        }
    }
}
