//
//  Platform.swift
//  FeedbackHubViewer
//
//  The platform differences the app actually cares about, in one place, so the
//  feature views stay free of `#if` noise. Anything that reads "on a Mac this,
//  on a phone that" belongs here rather than in a screen.
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

    /// Room is scarcer on a phone, so the padding a card or a tile takes is
    /// chosen once here instead of behind an `#if` in every component.
    static var cardPadding: CGFloat {
        #if os(macOS)
        return 16
        #else
        return 12
        #endif
    }

    static var tilePadding: CGFloat {
        #if os(macOS)
        return 14
        #else
        return 10
        #endif
    }
}
