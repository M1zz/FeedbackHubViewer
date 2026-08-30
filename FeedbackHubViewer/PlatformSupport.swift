//
//  PlatformSupport.swift
//  FeedbackHubViewer
//
//  Small shims that let the same views render on macOS and on iOS/iPadOS.
//  Everything platform-specific in the UI layer funnels through here so the
//  feature views stay free of #if noise.
//

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum Platform {
    /// Put a string on the system pasteboard.
    static func copyToPasteboard(_ string: String) {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        #else
        UIPasteboard.general.string = string
        #endif
    }

    /// The notification the system posts when this app is about to stop being
    /// frontmost — on a Mac, quitting; on a phone, being switched away from,
    /// after which the process can be killed without another word. The last
    /// moment to write anything that has to survive.
    static var willStopNotification: Notification.Name {
        #if os(macOS)
        return NSApplication.willTerminateNotification
        #else
        return UIApplication.didEnterBackgroundNotification
        #endif
    }

    /// Where the iCloud account is signed in, for user-facing copy.
    static var deviceNoun: String {
        #if os(macOS)
        return "Mac"
        #else
        return "기기"
        #endif
    }
}

/// A copy button that admits it worked.
///
/// Writing to the pasteboard produces no feedback of its own on either
/// platform, so the label does it: 복사 → 복사됨 for a moment, then back. The
/// text is captured at tap time, so a list row that scrolls away underneath it
/// changes nothing about what was copied.
struct CopyButton: View {
    let text: String
    var title: String = "복사"
    /// Compact form for a caption row: glyph only, borderless.
    var isCompact = false

    @State private var copied = false

    var body: some View {
        Button {
            Platform.copyToPasteboard(text)
            copied = true
        } label: {
            let label = Label(copied ? "복사됨" : title,
                              systemImage: copied ? "checkmark" : "doc.on.doc")
            if isCompact {
                label.labelStyle(.iconOnly).font(.caption)
            } else {
                label
            }
        }
        .buttonStyle(.borderless)
        .disabled(text.isEmpty)
        .help(copied ? "복사했습니다" : "클립보드로 복사")
        // Tied to `copied` rather than started inside the action: leaving the
        // view mid-countdown cancels the sleep instead of writing to state
        // that is already gone.
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            copied = false
        }
    }
}

/// Date formatting for the UI. The interface is written in Korean, so dates are
/// formatted in Korean too rather than following the device locale — otherwise
/// a Korean label ends up next to "3 weeks ago".
enum AppFormat {
    static let locale = Locale(identifier: "ko_KR")

    /// "2026. 8. 15. 오후 6:16"
    static func dateTime(_ date: Date) -> String {
        dateTimeFormatter.string(from: date)
    }

    /// "오후 6:16"
    static func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    /// "3주 전"
    static func relative(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    /// "1,240" — a running record count, grouped so a five-digit number is
    /// readable at a glance in the status line.
    static func count(_ value: Int) -> String {
        countFormatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private static let countFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .decimal
        return f
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = locale
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = locale
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = locale
        f.unitsStyle = .short
        return f
    }()
}

/// A project's App Store icon, falling back to the symbol the lists used to
/// show on its own.
///
/// Twenty apps are told apart by their icons far faster than by twenty names,
/// and the hub already knows every one of them: resolving bundle ids to store
/// apps is the first thing `KeywordStore` does on launch, and the result is on
/// disk. So this costs no request — only the image itself, which `URLSession`'s
/// shared cache keeps between launches.
///
/// The symbol stays as the fallback rather than a grey box, because "not on the
/// App Store" is a real state here: a Development-only build, or one still in
/// review, has no icon and should not look like one that failed to load.
struct AppIcon: View {
    let url: URL?
    var symbol: String = "app.dashed"
    var tint: Color = .accentColor
    var size: CGFloat = 22

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    // The rounded rectangle rather than the symbol: this is a
                    // moment, and a symbol that swaps for an icon reads as a
                    // flicker where a plate that fills in does not.
                    RoundedRectangle(cornerRadius: size * 0.22).fill(.quaternary)
                }
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
            } else {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.8))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Lays children out in a row and wraps to the next line when they don't fit.
///
/// Rows of badges (project · version · device · email) used to be a single
/// `HStack` with `lineLimit(1)`, which quietly dropped whatever didn't fit on a
/// phone. Wrapping keeps every value on screen.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var size = CGSize(width: 0, height: 0)
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let item = subview.sizeThatFits(.unspecified)
            if lineWidth > 0 && lineWidth + spacing + item.width > maxWidth {
                size.width = max(size.width, lineWidth)
                size.height += lineHeight + lineSpacing
                lineWidth = item.width
                lineHeight = item.height
            } else {
                lineWidth += (lineWidth > 0 ? spacing : 0) + item.width
                lineHeight = max(lineHeight, item.height)
            }
        }
        size.width = max(size.width, lineWidth)
        size.height += lineHeight
        return size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let item = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + item.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            // `.unspecified` so each child keeps the natural size it was
            // measured with; proposing the measured size back makes labels
            // re-lay out and drop their text.
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
            x += item.width + spacing
            lineHeight = max(lineHeight, item.height)
        }
    }
}

extension View {
    /// `navigationSubtitle` where the platform has it (macOS, iOS 26+); a thin
    /// bar pinned under the navigation bar on older iOS.
    @ViewBuilder
    func hubNavigationSubtitle(_ subtitle: String) -> some View {
        #if os(macOS)
        self.navigationSubtitle(subtitle)
        #else
        if #available(iOS 26.0, *) {
            self.navigationSubtitle(subtitle)
        } else {
            self.safeAreaInset(edge: .top, spacing: 0) {
                SubtitleBar(text: subtitle)
            }
        }
        #endif
    }

    /// Sidebar-flavoured list style per platform. On iOS the sidebar content is
    /// presented as a sheet, where the grouped style reads better.
    @ViewBuilder
    func hubSidebarListStyle() -> some View {
        #if os(macOS)
        self.listStyle(.sidebar)
        #else
        self.listStyle(.insetGrouped)
        #endif
    }

    /// The feedback list style: inset rows on macOS, plain rows on iOS so the
    /// custom row content owns its own padding.
    @ViewBuilder
    func hubListStyle() -> some View {
        #if os(macOS)
        self.listStyle(.inset)
        #else
        self.listStyle(.plain)
        #endif
    }
}

#if os(iOS)
/// The iOS stand-in for `navigationSubtitle`.
private struct SubtitleBar: View {
    let text: String

    var body: some View {
        HStack {
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}
#endif
