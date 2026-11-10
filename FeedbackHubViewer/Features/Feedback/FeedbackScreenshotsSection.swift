//
//  FeedbackScreenshotsSection.swift
//  FeedbackHubViewer
//
//  피드백 상세의 "첨부한 사진" 칸. 사용자가 증상을 찍어 붙인 사진을 내용 바로 아래에
//  보여 준다. 누르면 맥은 미리보기로 열고, 아이폰은 크게 띄운다.
//

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct FeedbackScreenshotsSection: View {
    @EnvironmentObject private var store: FeedbackStore
    let feedback: Feedback

    @State private var files: [URL] = []
    @State private var loading = true
    #if os(iOS)
    @State private var enlarged: Enlarged?

    private struct Enlarged: Identifiable {
        let url: URL
        var id: URL { url }
    }
    #endif

    private let thumbnailHeight: CGFloat = 220

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("첨부한 사진 \(feedback.screenshotKeys.count)장")
                .font(.title3.weight(.semibold))

            if loading && files.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("사진을 받는 중…")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            } else if files.isEmpty {
                Text("사진을 받지 못했어요. 잠시 뒤 다시 열어 보세요.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(files, id: \.self) { url in
                            Button { open(url) } label: {
                                FileImage(url: url)
                                    .frame(height: thumbnailHeight)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(Color.secondary.opacity(0.25)))
                            }
                            .buttonStyle(.plain)
                            .help("크게 보기")
                        }
                    }
                }
                if files.count < feedback.screenshotKeys.count {
                    Text("\(feedback.screenshotKeys.count - files.count)장은 받지 못했어요.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task(id: feedback.id) {
            loading = true
            files = await store.screenshots(for: feedback)
            loading = false
        }
        #if os(iOS)
        .sheet(item: $enlarged) { item in
            NavigationStack {
                ScrollView([.horizontal, .vertical]) {
                    FileImage(url: item.url)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("닫기") { enlarged = nil }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: item.url)
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        #endif
    }

    private func open(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        enlarged = Enlarged(url: url)
        #endif
    }
}

/// 파일에서 읽은 사진. 못 읽으면 회색 칸.
private struct FileImage: View {
    let url: URL

    var body: some View {
        #if os(macOS)
        if let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().scaledToFit()
        } else {
            placeholder
        }
        #else
        if let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image).resizable().scaledToFit()
        } else {
            placeholder
        }
        #endif
    }

    private var placeholder: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.12))
            .aspectRatio(9.0 / 19.5, contentMode: .fit)
            .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
    }
}
