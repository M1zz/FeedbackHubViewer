//
//  ListStyles.swift
//  FeedbackHubViewer
//
//  Per-platform chrome, named for what it is for rather than for which platform
//  it is on, so a feature view reads `.hubListStyle()` and never `#if os`.
//

import SwiftUI

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

    /// The bar that sits above a list: a section switch, a filter row, a set of
    /// actions. Same fill and same hairline wherever it appears.
    func hubHeaderBar(horizontalPadding: CGFloat = 12,
                      verticalPadding: CGFloat = 10) -> some View {
        self
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
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
