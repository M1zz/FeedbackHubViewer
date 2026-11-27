//
//  InAppNamesCard.swift
//  FeedbackHubViewer
//
//  인앱 상품 이름을 검색어 자리로 — 언어마다 상품 표시 이름에 검색어가 걸려 있는지 보고,
//  키워드 칸에 둔 말 중 아직 어느 상품 이름에도 없는 것을 넣을 거리로 보인다. 그 자리에서 고친다.
//

import SwiftUI

struct InAppNamesCard: View {
    @EnvironmentObject private var connect: AppStoreConnectStore
    let project: String

    @State private var names: [ProductLocaleName] = []
    @State private var error: String?
    @State private var isLoading = false
    @State private var locale: String?
    /// 고치는 중인 이름(현지화 id → 새 이름).
    @State private var drafts: [String: String] = [:]
    @State private var saving: Set<String> = []

    var body: some View {
        Card(title: "인앱 이름 검색어", systemImage: "bag") {
            if !connect.isConfigured {
                note("App Store Connect 키를 넣으면 인앱 상품 이름을 언어마다 읽습니다.")
            } else if isLoading && names.isEmpty {
                ProgressView("상품 이름을 읽는 중…").font(.body)
            } else if let error, names.isEmpty {
                Text(error).font(.body).foregroundStyle(.orange)
                Button("다시 읽기") { Task { await load() } }
            } else if names.isEmpty {
                note("이 앱에는 인앱 상품이 없습니다.")
            } else {
                content
            }
        }
        .task(id: project) { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            names = try await connect.productNames(bundleID: project)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private var locales: [String] { Array(Set(names.map(\.locale))).sorted() }

    private var selected: String {
        if let locale, locales.contains(locale) { return locale }
        return locales.contains("ko") ? "ko" : (locales.first ?? "")
    }

    private func appName(_ locale: String) -> String {
        connect.metadata[project]?.value?.live.locales[locale]?.name ?? connect.metadata[project]?.value?.live.locales["ko"]?.name ?? ""
    }

    @ViewBuilder
    private var content: some View {
        let empty = names.filter { $0.searchWords(appName: appName($0.locale)).isEmpty }
        note("App Store 검색은 상품 이름도 읽습니다. 키워드 칸 100자 밖에서 검색어를 더 거는 자리예요. 언어 \(locales.count)개 · 이름 \(names.count)칸 중 \(empty.count)칸은 상품 종류만 적혀 검색에 아무것도 걸지 않습니다. 바꾼 이름은 다음 앱 심사 때 같이 심사받습니다.")

        Picker("언어", selection: Binding(get: { selected }, set: { locale = $0 })) {
            ForEach(locales, id: \.self) { code in
                let missing = empty.filter { $0.locale == code }.count
                Text(missing > 0 ? "\(code)  ·  \(missing)" : code).tag(code)
            }
        }
        .fixedSize()
        .font(.body)

        let rows = names.filter { $0.locale == selected }.sorted { $0.product.name < $1.product.name }
        ForEach(rows) { row($0) }

        let ideas = suggestions(for: selected, rows: rows)
        if !ideas.isEmpty {
            Divider()
            Text("넣을 거리 — 키워드 칸에 둔 말 중 아직 상품 이름에 없는 것")
                .font(.headline)
            Text(ideas.joined(separator: " · "))
                .font(.body)
                .textSelection(.enabled)
        }
    }

    private func row(_ entry: ProductLocaleName) -> some View {
        let draft = drafts[entry.id] ?? entry.name
        let words = ProductLocaleName(id: entry.id, product: entry.product, locale: entry.locale, name: draft)
            .searchWords(appName: appName(entry.locale))
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(entry.product.name).font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Text(words.isEmpty ? "검색어 없음" : "검색어 " + words.joined(separator: ", "))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(words.isEmpty ? Color.orange : Color.green)
            }
            HStack(spacing: 8) {
                TextField("표시 이름", text: Binding(get: { draft }, set: { drafts[entry.id] = $0 }))
                    .textFieldStyle(.roundedBorder)
                Text("\(draft.count)/\(ProductLocaleName.limit)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(draft.count > ProductLocaleName.limit ? .red : .secondary)
                if draft != entry.name {
                    Button(saving.contains(entry.id) ? "저장 중…" : "저장") { Task { await save(entry, draft) } }
                        .disabled(saving.contains(entry.id) || draft.isEmpty || draft.count > ProductLocaleName.limit)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func save(_ entry: ProductLocaleName, _ name: String) async {
        saving.insert(entry.id)
        defer { saving.remove(entry.id) }
        do {
            try await connect.rename(entry, to: name)
            if let index = names.firstIndex(where: { $0.id == entry.id }) { names[index].name = name }
            drafts[entry.id] = nil
            error = nil
        } catch {
            self.error = "저장하지 못했습니다: \(error.localizedDescription)"
        }
    }

    /// 그 언어 키워드 칸의 말 중 어느 상품 이름에도 없는 것.
    private func suggestions(for locale: String, rows: [ProductLocaleName]) -> [String] {
        guard let keywords = connect.metadata[project]?.value?.live.locales[locale]?.keywords else { return [] }
        let used = Set(rows.flatMap { ProductLocaleName.words($0.name) })
        return keywords.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && ProductLocaleName.words($0).allSatisfy { !used.contains($0) } }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
