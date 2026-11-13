//
//  SupportersView.swift
//  FeedbackHubViewer
//
//  "고마운 분들" 칸 — 앱 하나면 그 앱의 분들과 적는 칸, 전체면 앱마다 묶어서.
//  후원 건수(판매 리포트)를 옆에 두어 이름을 받은 분이 몇 중 몇인지 보인다.
//

import SwiftUI

struct SupportersView: View {
    /// nil == 전체 앱.
    let project: String?

    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var purchases: AppStoreConnectStore
    @ObservedObject private var supporters = SupportersStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let project {
                    tipCard(project)
                    SupporterAddCard(project: project)
                    listCard(supporters.supporters(for: project), showsApp: false)
                } else {
                    overview
                }
            }
            .padding(Platform.cardPadding)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 전체

    @ViewBuilder private var overview: some View {
        let byApp = Dictionary(grouping: supporters.supporters(for: nil), by: \.project)
        if byApp.isEmpty {
            Card(title: "아직 적은 분이 없습니다", systemImage: "heart") {
                Text("앱을 하나 골라 이 칸에서 함께 만든 분 · 후원해 준 분을 적습니다. 지금은 허브에만 보입니다.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        } else {
            ForEach(byApp.keys.sorted { store.displayName(for: $0) < store.displayName(for: $1) }, id: \.self) { key in
                Button {
                    store.open(project: key, section: .supporters)
                } label: {
                    listCard(byApp[key] ?? [], title: store.displayName(for: key), showsApp: true)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 한 앱

    /// 최근 판매 리포트의 팁 건수. 이름은 App Store 가 주지 않는다.
    @ViewBuilder private func tipCard(_ project: String) -> some View {
        if let tips = tipCount(project) {
            let named = supporters.supporters(for: project).filter { $0.kind == .donor }.count
            Card(title: "최근 \(AppStoreConnectStore.salesDays)일 후원 \(tips)건", systemImage: "cup.and.saucer") {
                Text("App Store 는 누가 냈는지 알려 주지 않습니다. 후원한 분이 메일로 이름과 주문 번호를 보내 오면 아래에 적습니다. 지금까지 이름을 적은 후원자 \(named)명.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 팁 상품(`….tip.…`)의 최근 결제 건수. 팁 상품이 없거나 판매를 못 읽었으면 nil.
    private func tipCount(_ project: String) -> Int? {
        guard let sales = purchases.sales,
              let tips = purchases.products(for: project)?.filter({ $0.productID.lowercased().contains(".tip") }),
              !tips.isEmpty else { return nil }
        return tips.reduce(0) { $0 + sales.totals(for: $1.id).purchases }
    }

    private func listCard(_ list: [Supporter], title: String? = nil, showsApp: Bool) -> some View {
        Card(title: title ?? "고마운 분들 \(list.count)명", systemImage: "heart.text.square") {
            if list.isEmpty {
                Text("아직 없습니다.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            ForEach(Supporter.Kind.allCases) { kind in
                let people = list.filter { $0.kind == kind }
                if !people.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("\(kind.title) \(people.count)명", systemImage: kind.systemImage)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(kind == .donor ? .pink : .accentColor)
                        ForEach(people) { person in
                            row(person, removable: !showsApp)
                        }
                    }
                }
            }
        }
    }

    private func row(_ person: Supporter, removable: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(person.name)
                .font(.body.weight(.medium))
            if !person.note.isEmpty {
                Text(person.note)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(AppFormat.relative(person.addedAt))
                .font(.caption)
                .foregroundStyle(.tertiary)
            if removable {
                Button(role: .destructive) {
                    supporters.remove(person)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("목록에서 빼기")
            }
        }
        .contextMenu {
            if !person.orderID.isEmpty {
                Text("주문 번호 \(person.orderID)")
            }
        }
    }
}

/// 한 분을 적는 칸.
private struct SupporterAddCard: View {
    let project: String

    @ObservedObject private var supporters = SupportersStore.shared
    @State private var name = ""
    @State private var kind: Supporter.Kind = .chosen
    @State private var note = ""
    @State private var orderID = ""

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var duplicateOrder: Bool { kind == .donor && supporters.hasOrder(orderID) }

    var body: some View {
        Card(title: "한 분 적기", systemImage: "plus.circle") {
            Picker("어떤 분", selection: $kind) {
                ForEach(Supporter.Kind.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            TextField("이름 · 닉네임 (보여 줄 이름 그대로)", text: $name)
                .textFieldStyle(.roundedBorder)
            TextField(kind == .donor ? "무엇을 (예: 커피 한 잔)" : "무엇을 해 줬나 (예: 일본어 번역, 첫 베타 테스터)", text: $note)
                .textFieldStyle(.roundedBorder)
            if kind == .donor {
                TextField("주문 번호 Order ID (영수증 메일, 없으면 비움)", text: $orderID)
                    .textFieldStyle(.roundedBorder)
                if duplicateOrder {
                    Text("이미 적은 주문 번호입니다.")
                        .font(.body)
                        .foregroundStyle(.orange)
                }
            }
            Button("적기") {
                supporters.add(Supporter(project: project, name: trimmedName, kind: kind,
                                         note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                                         orderID: kind == .donor ? orderID.trimmingCharacters(in: .whitespaces) : ""))
                name = ""; note = ""; orderID = ""
            }
            .buttonStyle(.borderedProminent)
            .disabled(trimmedName.isEmpty || duplicateOrder)
        }
    }
}
