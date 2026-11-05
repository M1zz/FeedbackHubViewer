//
//  GiftCodesView.swift
//  FeedbackHubViewer
//
//  "선물 코드" 칸 — Pro 선물용 App Store 오퍼 코드 묶음. 앱 하나면 그 앱의 남은 장 · 나간 장 · 예비와
//  코드 파일 넣기, 전체면 묶음이 있는 앱을 남은 장이 적은 것부터. 어떻게 도는지는 아래에 한 번 적는다.
//

import SwiftUI

struct GiftCodesView: View {
    /// nil == 전체 앱.
    let project: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GiftCodePoolCard(project: project)
                Card(title: "어떻게 도나", systemImage: "arrow.triangle.branch") {
                    DisclosureGroup("펼쳐 보기") {
                    VStack(alignment: .leading, spacing: 8) {
                        step("1", "'App Store Connect 로 채우기'(전체 앱에서는 '전부 채우기')를 누르면 Pro(비소모성) 상품에 \"\(AppStoreConnect.giftOfferName)\" 무료 오퍼 코드를 만들고 일회용 코드를 받습니다.")
                        step("2", "\(GiftCodePool.targetSize)장을 iCloud 공개 DB 에 올립니다. App Store Connect 에서 받은 코드 파일을 넣어도 되고, 그때 넘치는 것은 이 기기에 예비로 둡니다.")
                        step("3", "앱에서 누가 Pro 선물(소모성)을 사면 그 앱이 묶음에서 한 장을 가져가 App Store 사용 링크로 공유합니다.")
                        step("4", "받은 사람은 링크를 누르고 '사용' 한 번. Pro 를 여는 것은 App Store 입니다.")
                        step("5", "이 칸을 열 때마다 나간 장과 곧 끝나는 장을 지우고, \(GiftCodePool.autoTopUpMark)장 아래면 다시 \(GiftCodePool.targetSize)장까지 채웁니다.")
                    }
                    .padding(.top, 6)
                    }
                    .font(.body)
                }
            }
            .padding(Platform.cardPadding)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func step(_ number: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(number)
                .font(.body.weight(.bold).monospacedDigit())
                .foregroundStyle(.tint)
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
