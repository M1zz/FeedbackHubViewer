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

    /// Where the iCloud account is signed in, for user-facing copy.
    static var deviceNoun: String {
        #if os(macOS)
        return "Mac"
        #else
        return "기기"
        #endif
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
