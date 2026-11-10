//
//  FeedbackScreenshotsSection.swift
//  FeedbackHubViewer
//
//  사용자가 피드백에 붙인 사진.
//  - 상세의 "첨부한 사진" 칸: 내용 바로 아래 큰 사진.
//  - 목록 줄의 작은 사진 띠: 상세를 열지 않고 바로 본다.
//  어느 쪽이든 누르면 맥은 미리보기로 열고, 아이폰은 크게 띄워 공유할 수 있다.
//

import SwiftUI
import ImageIO
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - 상세 칸

struct FeedbackScreenshotsSection: View {
    let feedback: Feedback

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("첨부한 사진 \(feedback.screenshotKeys.count)장")
                .font(.title3.weight(.semibold))
            FeedbackScreenshotStrip(feedback: feedback, height: 220, showsStatus: true)
        }
    }
}

// MARK: - 사진 띠 (상세 · 목록 공용)

struct FeedbackScreenshotStrip: View {
    @EnvironmentObject private var store: FeedbackStore
    let feedback: Feedback
    let height: CGFloat
    /// 받는 중 · 못 받음을 글로 알린다. 목록 줄은 자리만 회색으로 두고 글은 뺀다.
    var showsStatus = false

    @State private var files: [URL] = []
    @State private var loading = true
    #if os(iOS)
    @State private var enlarged: Enlarged?

    private struct Enlarged: Identifiable {
        let url: URL
        var id: URL { url }
    }
    #endif

    var body: some View {
        content
            .task(id: feedback.id) {
                loading = true
                files = await store.screenshots(for: feedback)
                loading = false
            }
            #if os(iOS)
            .sheet(item: $enlarged) { item in
                NavigationStack {
                    ScrollView([.horizontal, .vertical]) {
                        FileImage(url: item.url, maxPixel: nil)
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

    @ViewBuilder
    private var content: some View {
        let expected = feedback.screenshotKeys.count
        if files.isEmpty {
            if showsStatus {
                if loading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("사진을 받는 중…")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("사진을 받지 못했어요. 잠시 뒤 다시 열어 보세요.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            } else {
                // 목록 줄: 받는 동안 사진 자리만 잡아 둬 줄 높이가 튀지 않게.
                HStack(spacing: 8) {
                    ForEach(0..<expected, id: \.self) { _ in
                        Placeholder().frame(height: height)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: height > 100 ? 12 : 8) {
                        ForEach(files, id: \.self) { url in
                            Button { open(url) } label: {
                                FileImage(url: url, maxPixel: height * 3)
                                    .frame(height: height)
                                    .clipShape(RoundedRectangle(cornerRadius: height > 100 ? 8 : 6))
                                    .overlay(RoundedRectangle(cornerRadius: height > 100 ? 8 : 6)
                                        .strokeBorder(Color.secondary.opacity(0.25)))
                            }
                            .buttonStyle(.plain)
                            .help("크게 보기")
                        }
                    }
                }
                if showsStatus, !loading, files.count < expected {
                    Text("\(expected - files.count)장은 받지 못했어요.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func open(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        enlarged = Enlarged(url: url)
        #endif
    }
}

// MARK: - 파일 사진

/// 파일에서 읽은 사진. `maxPixel` 이 있으면 그 크기로 줄여 읽는다 — 목록 줄마다
/// 원본을 통째로 풀면 스크롤이 무거워진다. 못 읽으면 회색 칸.
private struct FileImage: View {
    let url: URL
    let maxPixel: CGFloat?

    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
            } else {
                Placeholder()
            }
        }
        .task(id: url) {
            image = await Task.detached(priority: .userInitiated) { [url, maxPixel] in
                Self.load(url, maxPixel: maxPixel)
            }.value
        }
    }

    nonisolated private static func load(_ url: URL, maxPixel: CGFloat?) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        if let maxPixel { options[kCGImageSourceThumbnailMaxPixelSize] = Int(maxPixel) }
        else { return CGImageSourceCreateImageAtIndex(source, 0, nil) }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

private struct Placeholder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.secondary.opacity(0.12))
            .aspectRatio(9.0 / 19.5, contentMode: .fit)
            .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
    }
}
