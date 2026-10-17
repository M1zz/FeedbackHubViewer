//
//  SettingsView.swift
//  FeedbackHubViewer
//
//  설정 — App Store Connect 연결, 그리고 어떤 것을 뱃지 · 알림으로 볼지.
//
//  연결 폼은 원래 "앱 내 구입" 화면 안에 있었는데, 그 키는 앱 내 구입만이 아니라 키워드
//  화면의 메타데이터 · 노출 카드도 쓴다. 한 화면 안에 두면 다른 화면에서는 "어디서 넣지"가
//  된다. 그래서 맥은 표준 설정 창(⌘,), 아이폰 · 아이패드는 "더 보기"의 설정 시트로 뺐다.
//

import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import ServiceManagement
#endif

struct SettingsView: View {
    @EnvironmentObject private var connect: AppStoreConnectStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if os(macOS)
        TabView {
            ScrollView { connectSection.padding(20) }
                .tabItem { Label("App Store Connect", systemImage: "key") }
            ScrollView { AttentionSettings().padding(20) }
                .tabItem { Label("알림", systemImage: "bell.badge") }
        }
        .frame(width: 560, height: 620)
        #else
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    AttentionSettings()
                    Divider()
                    connectSection
                }
                .padding()
            }
                .navigationTitle("설정")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("완료") { dismiss() }
                    }
                }
        }
        #endif
    }

    private var connectSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(connect.isConfigured ? "연결됨" : "연결 안 됨",
                  systemImage: connect.isConfigured ? "checkmark.circle.fill" : "xmark.circle")
                .font(.headline)
                .foregroundStyle(connect.isConfigured ? .green : .secondary)
            Text("이 키로 \"앱 내 구입\"의 상품 · 판매와, 키워드 화면의 스토어 메타데이터 · 노출 · 전환을 읽습니다.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ConnectKeyForm(onSaved: {})
        }
    }
}

// MARK: - 알림

/// 무엇을 뱃지(앱 아이콘 · 종 · 탭)로 세고, 무엇이 오면 시스템 알림을 띄울지.
/// 뱃지는 리뷰 → 피드백 → 진단 순으로 선다 — 이 목록의 순서가 그 우선순위다.
private struct AttentionSettings: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var news: NewsStore

    /// 시스템 알림을 띄울 수 있는 것 - 뱃지와 같은 순서.
    private let alertable: [AttentionKind] = [.review, .feedback, .crash]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("뱃지").font(.headline)
                Text("앱 아이콘 · 툴바의 종 · 탭에 새로 온 수를 붙일 것. 켠 것 가운데 새 리뷰가 맨 앞, 그다음 피드백, 진단 순으로 보입니다.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(AttentionKind.allCases) { kind in
                    Toggle(isOn: binding(for: kind, in: \.badgeKinds)) {
                        Label("새 \(kind.name)", systemImage: kind.systemImage)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("알림").font(.headline)
                Toggle(isOn: $store.notificationsEnabled) {
                    Label("새것이 오면 이 기기에 알림 보내기", systemImage: "bell")
                }
                ForEach(alertable) { kind in
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle(isOn: binding(for: kind, in: \.alertKinds)) {
                            Label("새 \(kind.name)", systemImage: kind.systemImage)
                        }
                        .disabled(!store.notificationsEnabled)
                        if store.notificationsEnabled && store.alertKinds.contains(kind) {
                            Text(how(kind))
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.leading, 28)
                        }
                    }
                    .padding(.leading, 20)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Toggle(isOn: $news.alertsEnabled) {
                        Label("내 앱 소식", systemImage: "newspaper")
                    }
                    .disabled(!store.notificationsEnabled)
                    if store.notificationsEnabled && news.alertsEnabled {
                        Text("차트 진입 · 스토어 소개 흔적 · 새 링크 · 바깥 기사 · 출시 · 거절 · 적신호는 찾는 대로, 나머지(최고 기록 · 이정표 · 키워드 10위 · 새 나라)는 아침 9시에 묶어서 알립니다.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, 28)
                    }
                }
                .padding(.leading, 20)
                Text("사용 통계 · 차트 같은 숫자는 하루에 한 번만 저절로 다시 읽습니다. 바로 보려면 새로고침(⌘R)을 누르세요.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                #if os(macOS)
                LoginItemToggle()
                #endif
                if store.notificationsEnabled && !store.notificationsAuthorized {
                    Text("시스템 설정에서 이 앱의 알림을 허용해야 알림이 표시됩니다.")
                        .font(.body)
                        .foregroundStyle(.orange)
                }
            }
        }
        .font(.body)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 그 종류가 어떻게 오는지. 푸시가 걸렸는지는 기기마다 다르다.
    private func how(_ kind: AttentionKind) -> String {
        switch kind {
        case .review:
            #if os(macOS)
            return "App Store 는 리뷰를 푸시로 알려 주지 않아서, 앱이 떠 있는 동안 30분마다 확인합니다. 창을 닫아도 앱이 떠 있으면 확인합니다."
            #else
            return "App Store 는 리뷰를 푸시로 알려 주지 않아서, iOS 가 허락할 때 뒤에서 확인합니다. 몇 시간 늦을 수 있습니다."
            #endif
        case .feedback, .crash:
            return store.pushKinds.contains(kind)
                ? "푸시로 받습니다 - 앱이 꺼져 있어도 옵니다."
                : "푸시를 걸지 못해 앱이 떠 있을 때만 옵니다(iCloud 로그인 · 네트워크 확인)."
        }
    }

    private func binding(for kind: AttentionKind,
                         in keyPath: ReferenceWritableKeyPath<FeedbackStore, Set<AttentionKind>>) -> Binding<Bool> {
        Binding {
            store[keyPath: keyPath].contains(kind)
        } set: { isOn in
            if isOn { store[keyPath: keyPath].insert(kind) } else { store[keyPath: keyPath].remove(kind) }
        }
    }
}

/// 설정을 여는 버튼. 맥은 설정 창을, 아이폰 · 아이패드는 설정 시트를 연다.
struct OpenSettingsButton: View {
    @EnvironmentObject private var connect: AppStoreConnectStore
    var title = "설정"

    var body: some View {
        #if os(macOS)
        SettingsLink {
            Label(title, systemImage: "gearshape")
        }
        #else
        Button {
            connect.isShowingSettings = true
        } label: {
            Label(title, systemImage: "gearshape")
        }
        #endif
    }
}

// MARK: - 키 입력

struct ConnectKeyForm: View {
    @EnvironmentObject private var purchases: AppStoreConnectStore
    let onSaved: () -> Void

    @State private var issuerID = ""
    @State private var keyID = ""
    @State private var privateKey = ""
    @State private var vendorNumber = ""
    @State private var error: String?
    @State private var isImporting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("App Store Connect → 사용자 및 액세스 → 통합 → App Store Connect API에서 팀 키를 만들고, 아래 세 값을 넣어 주세요. 키는 iCloud 키체인에 저장되어 같은 Apple 계정의 다른 기기(맥 · 아이폰 · 아이패드)에도 저절로 들어갑니다.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            field("Issuer ID", text: $issuerID, prompt: "57246542-96fe-1a63-e053-0824d011072a")
            field("Key ID", text: $keyID, prompt: "2X9R4HXF34")

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("개인 키 (.p8)").font(.headline)
                    Spacer()
                    Button("파일에서 불러오기") { isImporting = true }
                        .font(.body)
                }
                TextEditor(text: $privateKey)
                    .font(.body.monospaced())
                    .frame(minHeight: 110)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
                Text("키는 만들 때 한 번만 내려받을 수 있습니다. 잃어버렸으면 새로 만들어야 해요.")
                    .font(.body)
                    .foregroundStyle(.tertiary)
            }

            field("판매자 번호 (선택)", text: $vendorNumber, prompt: "8xxxxxxx")
            Text("판매 리포트용입니다. \"판매 및 추세\" 화면 왼쪽 위에 있어요. 판매 리포트까지 읽으려면 키 역할이 Admin 또는 Finance여야 합니다.")
                .font(.body)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            if let error {
                Text(error)
                    .font(.body)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("저장") { save() }
                    .buttonStyle(.borderedProminent)
                if purchases.isConfigured {
                    Button("키 지우기", role: .destructive) {
                        purchases.signOut()
                        onSaved()
                    }
                    .help("iCloud 키체인의 키를 지웁니다. 같은 Apple 계정의 모든 기기에서 지워집니다.")
                }
            }
            .font(.body)

            if purchases.isConfigured {
                // 다른 기기로 가는지 — 안 간다면 왜인지와 무엇을 켜면 되는지.
                if purchases.isKeySynced {
                    Label("iCloud 키체인에 저장됨 · 다른 기기에도 들어갑니다", systemImage: "checkmark.icloud")
                        .font(.callout)
                        .foregroundStyle(.green)
                } else {
                    Label("이 기기에만 저장됨 · 설정 → Apple 계정 → iCloud → 암호 및 키체인을 켜고 다시 저장하면 다른 기기로 갑니다",
                          systemImage: "icloud.slash")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear {
            guard let saved = purchases.credentials else { return }
            issuerID = saved.issuerID
            keyID = saved.keyID
            privateKey = saved.privateKey
            vendorNumber = saved.vendorNumber ?? ""
        }
        .fileImporter(isPresented: $isImporting,
                      allowedContentTypes: [UTType(filenameExtension: "p8") ?? .data, .data]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                privateKey = text
                // AuthKey_2X9R4HXF34.p8 — 파일 이름에 Key ID가 들어 있다.
                let name = url.deletingPathExtension().lastPathComponent
                if keyID.isEmpty, name.hasPrefix("AuthKey_") {
                    keyID = String(name.dropFirst("AuthKey_".count))
                }
            } else {
                error = "파일을 읽지 못했습니다."
            }
        }
    }

    private func field(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            TextField(title, text: text, prompt: Text(prompt))
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
        }
    }

    private func save() {
        let vendor = vendorNumber.trimmingCharacters(in: .whitespaces)
        let credentials = AppStoreConnectCredentials(
            issuerID: issuerID.trimmingCharacters(in: .whitespaces),
            keyID: keyID.trimmingCharacters(in: .whitespaces),
            privateKey: privateKey,
            vendorNumber: vendor.isEmpty ? nil : vendor)
        do {
            try purchases.save(credentials)
            error = nil
            onSaved()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

#if os(macOS)
/// 맥에 로그인하면 허브가 저절로 떠서 리뷰를 계속 본다.
private struct LoginItemToggle: View {
    @State private var isOn = SMAppService.mainApp.status == .enabled
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(get: { isOn }, set: set)) {
                Label("로그인할 때 열기", systemImage: "power")
            }
            Text(problem ?? "켜 두면 맥을 켤 때마다 허브가 떠서 새 리뷰를 놓치지 않습니다.")
                .font(.body)
                .foregroundStyle(problem == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            problem = nil
        } catch {
            problem = "바꾸지 못했습니다: \(error.localizedDescription)"
        }
        isOn = SMAppService.mainApp.status == .enabled
    }
}
#endif
