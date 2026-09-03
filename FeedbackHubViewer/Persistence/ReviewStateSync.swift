//
//  ReviewStateSync.swift
//  FeedbackHubViewer
//
//  "이건 확인했다 / 반영했다"를 기기 사이에서 하나로.
//
//  허브의 레코드는 앱들이 쓴 것이고, 이 뷰어는 그 Public 데이터베이스에 **읽기
//  권한만** 있다. 그래서 사람이 내리는 판단 — 읽음, 반영함/반영 안 함, 메모 — 은
//  레코드에 적을 수가 없고 지금까지 `UserDefaults`에 기기별로만 남았다. 맥에서
//  처리를 끝낸 피드백이 아이폰에서는 여전히 "확인 필요"로 떠 있었고, 그러면
//  어느 쪽 화면도 믿을 수 없게 된다.
//
//  그래서 같은 iCloud 계정이 공유하는 키·값 저장소
//  (`NSUbiquitousKeyValueStore`)에 둔다. CloudKit 레코드가 아니라 이쪽인 이유:
//
//   · 이 데이터는 남의 레코드에 대한 **내 메모**다. 컨테이너의 주인은 앱들이고,
//     뷰어가 거기에 쓸 자리는 없다.
//   · 크기가 사람이 내린 판단의 수만큼이다. 레코드 이름 하나가 40바이트 남짓,
//     천 건을 처리해도 100KB가 안 된다 — 1MB 한도와는 거리가 멀다.
//   · 켜고 끌 것이 없다. 로그인이 없거나 iCloud가 꺼져 있으면 로컬 미러
//     (`UserDefaults`)만으로 지금까지와 똑같이 동작하고, 나중에 로그인하면
//     그때 합쳐진다.
//
//  ## 합치는 규칙
//
//  두 기기가 각자 오프라인에서 고쳤을 때 무엇이 이기는가 — 키·값 저장소는
//  키 단위 마지막 쓰기 승리라서, 통째로 덮어쓰면 한쪽의 하루가 사라진다.
//  그래서 저장하기 전에 언제나 합친다:
//
//   · **읽음**은 늘어나기만 하는 집합이라 합집합이다. "다시 안 읽음으로"가
//     없으므로 합집합으로 잃을 것이 없다.
//   · **처리**는 레코드마다 `decidedAt`이 늦은 쪽이 이긴다. 그래서 "확인
//     필요로 되돌리기"도 항목을 지우는 대신 시각을 가진 빈 항목으로 남긴다
//     (`FeedbackStore.apply`) — 지웠다는 사실은 전할 수 없지만, 되돌렸다는
//     사실은 시각과 함께 전할 수 있다.
//
//  환경마다 키를 나눈다. Development와 Production은 서로 다른 레코드를 보므로
//  판단도 섞이면 안 된다 — 캐시 파일이 환경별로 나뉜 것과 같은 이유다.
//

import Foundation

/// 기기 사이에서 공유하는 검토 상태.
struct ReviewState: Codable {
    /// 이미 열어 본 레코드 이름.
    var readIDs: Set<String> = []
    /// 레코드 이름 → 무엇을 결정했는지.
    var triage: [String: FeedbackTriageEntry] = [:]

    var isEmpty: Bool { readIDs.isEmpty && triage.isEmpty }

    /// 두 기기가 각자 고친 것을 하나로. 파일 머리말의 규칙 그대로다.
    func merged(with other: ReviewState) -> ReviewState {
        var result = self
        result.readIDs.formUnion(other.readIDs)
        for (id, incoming) in other.triage {
            guard let mine = result.triage[id] else {
                result.triage[id] = incoming
                continue
            }
            if incoming.decidedAt > mine.decidedAt { result.triage[id] = incoming }
        }
        return result
    }
}

/// iCloud 키·값 저장소 한 겹.
///
/// 쓸 수 없는 상태(엔타이틀먼트 없음, 로그인 없음, iCloud Drive 꺼짐)를 오류로
/// 다루지 않는다. 이 앱은 저장소가 없어도 지금까지처럼 동작해야 하고, 없다는
/// 사실은 설정 화면에서 한 줄로 알려 주면 될 일이다.
@MainActor
final class ReviewStateSync {

    static let shared = ReviewStateSync()

    private let store = NSUbiquitousKeyValueStore.default
    private var observer: NSObjectProtocol?

    /// 저장소가 실제로 응답하는지. `synchronize()`는 엔타이틀먼트가 없으면
    /// false를 돌려주므로, 이 한 번이 "쓸 수 있는가"에 대한 답이다.
    private(set) var isAvailable = false

    /// 환경별 키. 값이 하나뿐인 이유는 읽음과 처리가 언제나 함께 합쳐지기
    /// 때문이다 — 둘을 따로 쓰면 한쪽만 반영된 중간 상태가 생긴다.
    private var key: String {
        "reviewState-\(CloudKitEnvironment.current.restPathComponent)"
    }

    private init() {}

    /// 저장소를 켜고, 다른 기기가 바꾼 것을 받기 시작한다.
    /// `onChange`는 이미 합쳐진 상태로 불린다.
    func start(onRemoteChange: @escaping (ReviewState) -> Void) {
        isAvailable = store.synchronize()
        guard isAvailable else { return }

        // 클로저는 메인 큐에서 불리지만 격리되지는 않으므로, 액터에 묶인 것은
        // 여기서 미리 꺼내 둔다.
        let watchedKey = key
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { note in
            // 이 키가 안 바뀐 알림도 온다(다른 키, 또는 계정 전환). 우리 키가
            // 목록에 없으면 할 일이 없다 — 계정이 바뀐 경우만 예외로, 그때는
            // 저장소 전체가 갈아끼워지므로 무조건 다시 읽는다.
            let changedKeys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
            let reason = note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            let accountChanged = reason == NSUbiquitousKeyValueStoreAccountChange
            guard accountChanged || changedKeys?.contains(watchedKey) == true else { return }
            Task { @MainActor [weak self] in
                guard let state = self?.load() else { return }
                onRemoteChange(state)
            }
        }
    }

    /// 저장소에 있는 것. 없거나 못 읽으면 nil.
    func load() -> ReviewState? {
        guard let data = store.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ReviewState.self, from: data)
    }

    /// 저장소의 것과 합쳐서 쓰고, 합친 결과를 돌려준다.
    ///
    /// 통째로 덮어쓰지 않는 이유는 머리말에 있다. 돌려주는 값이 곧 이 기기가
    /// 화면에 들고 있어야 할 상태다 — 다른 기기가 먼저 해 둔 판단이 여기서
    /// 함께 들어온다.
    @discardableResult
    func save(_ state: ReviewState) -> ReviewState {
        guard isAvailable else { return state }
        let merged = state.merged(with: load() ?? ReviewState())
        guard let data = try? JSONEncoder().encode(merged) else { return merged }
        store.set(data, forKey: key)
        // `synchronize()`는 디스크에 적어 두는 것까지다. 실제 업로드는 시스템이
        // 알아서 하고, 언제 할지는 우리가 정하지 않는다.
        store.synchronize()
        return merged
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}
