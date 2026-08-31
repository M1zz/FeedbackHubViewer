//
//  AppIcon.swift
//  FeedbackHubViewer
//
//  A project's App Store icon, falling back to the symbol the lists used to
//  show on its own.
//
//  Twenty apps are told apart by their icons far faster than by twenty names,
//  and the hub already knows every one of them: resolving bundle ids to store
//  apps is the first thing `KeywordStore` does on launch, and the result is on
//  disk. So this costs no request — only the image itself, which `URLSession`'s
//  shared cache keeps between launches.
//
//  The symbol stays as the fallback rather than a grey box, because "not on the
//  App Store" is a real state here: a Development-only build, or one still in
//  review, has no icon and should not look like one that failed to load.
//

import SwiftUI

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
