//
//  StoreLinkField.swift
//  FeedbackHubViewer
//
//  "스토어에 없음" 인 앱을 App Store 링크로 손수 잇는 칸.
//
//  허브는 앱이 보내 온 번들 ID 로 App Store 를 찾는다. 리포의 번들 ID 를 바꿨는데 스토어에는
//  옛 ID 로 나가 있으면(팔랑북) 저절로는 영영 못 찾는다. 스토어 링크 하나면 id 로 바로 잇는다.
//

import SwiftUI

struct StoreLinkField: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var keywords: KeywordStore
    let project: String
    var onLinked: () -> Void = {}

    @State private var link = ""
    @State private var isLinking = false
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("App Store 에 나와 있는데 못 찾았다면, 그 앱의 스토어 링크를 붙여 이어 주세요. 번들 ID 가 스토어의 것과 다를 때 그래요.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                TextField("https://apps.apple.com/kr/app/…/id1234567890", text: $link)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    #endif
                    .onSubmit(connect)
                if isLinking {
                    ProgressView().controlSize(.small)
                } else {
                    Button("잇기", action: connect)
                        .buttonStyle(.borderedProminent)
                        .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            if let problem {
                Text(problem)
                    .font(.body)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func connect() {
        guard !isLinking else { return }
        isLinking = true
        problem = nil
        Task {
            problem = await keywords.link(project: project, storeLink: link)
            isLinking = false
            if problem == nil { onLinked() }
        }
    }
}

/// 앱 목록의 오른쪽 클릭 메뉴에서 여는 시트.
struct StoreLinkSheet: View {
    @EnvironmentObject private var store: FeedbackStore
    let project: String
    let close: () -> Void

    var body: some View {
        NavigationStack {
            StoreLinkField(project: project, onLinked: close)
                .padding(20)
                .navigationTitle("\(store.displayName(for: project)) · App Store 와 잇기")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("닫기", action: close) }
                }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 220)
        #endif
    }
}
