//
//  SupportersStore.swift
//  FeedbackHubViewer
//
//  "고마운 분들" — 앱마다 이 앱이 여기까지 오게 해 준 사람. 내가 고른 분과 후원해 준 분.
//
//  App Store 는 누가 팁을 냈는지 알려 주지 않는다. 그래서 이름은 사람이 적는다 — 후원한 분은
//  팁 화면 안내대로 이름과 주문 번호(Order ID)를 메일로 보내 온다(LeeoKit `LeeoTipJarView`).
//  허브는 판매 리포트에서 팁 건수만 옆에 보여 준다(이름 받은 분이 몇 중 몇인지).
//
//  지금은 허브에서만 본다. 모아 보다가 앱 · 웹의 '고마운 사람들' 자리에 내보낼 때 이 목록이 원본이 된다.
//  기기 사이에서는 iCloud 키·값 저장소로 맞춘다(`SyncedDefaults`, 마지막 쓰기가 이긴다).
//

import Foundation

struct Supporter: Codable, Identifiable, Hashable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        /// 내가 고른 분 — 피드백 · 베타 · 번역 · 아이디어로 앱을 키워 준 사람.
        case chosen
        /// 팁(후원)을 내 준 분.
        case donor

        var id: String { rawValue }
        var title: String {
            switch self {
            case .chosen: "함께 만든 분"
            case .donor: "후원해 준 분"
            }
        }
        var systemImage: String {
            switch self {
            case .chosen: "person.2.fill"
            case .donor: "heart.fill"
            }
        }
    }

    var id = UUID()
    /// 앱 번들 ID.
    var project: String
    var name: String
    var kind: Kind
    /// 무엇을 해 줬나 — "일본어 번역", "커피 한 잔".
    var note: String = ""
    /// 후원이면 App Store 영수증의 주문 번호. 같은 분을 두 번 적지 않게 하는 데 쓴다.
    var orderID: String = ""
    var addedAt = Date()
}

@MainActor
final class SupportersStore: ObservableObject {
    static let shared = SupportersStore()
    static let defaultsKey = "supporters"

    @Published private(set) var all: [Supporter] = []

    private var observer: NSObjectProtocol?

    private init() {
        load()
        observer = NotificationCenter.default.addObserver(forName: SyncedDefaults.changed, object: nil,
                                                          queue: .main) { [weak self] note in
            guard (note.userInfo?["keys"] as? [String])?.contains(Self.defaultsKey) ?? true else { return }
            MainActor.assumeIsolated { self?.load() }
        }
    }

    /// 한 앱의 분들, 먼저 적은 분부터. nil == 전체.
    func supporters(for project: String?) -> [Supporter] {
        all.filter { project == nil || $0.project == project }.sorted { $0.addedAt < $1.addedAt }
    }

    func add(_ supporter: Supporter) {
        all.append(supporter)
        save()
    }

    func remove(_ supporter: Supporter) {
        all.removeAll { $0.id == supporter.id }
        save()
    }

    /// 이미 적은 주문 번호인가 — 같은 후원을 두 번 적지 않게.
    func hasOrder(_ orderID: String) -> Bool {
        let id = orderID.trimmingCharacters(in: .whitespaces)
        return !id.isEmpty && all.contains { $0.orderID.caseInsensitiveCompare(id) == .orderedSame }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let list = try? JSONDecoder().decode([Supporter].self, from: data) else { return }
        all = list
    }

    private func save() {
        SyncedDefaults.set(try? JSONEncoder().encode(all), forKey: Self.defaultsKey)
    }
}
