//
//  Storefront.swift
//  FeedbackHubViewer
//
//  Which App Store a rank check is asking about. A country changes the whole
//  answer, so it is never implied — every check carries one.
//

import Foundation

/// The storefronts a check can ask about. Not an exhaustive list of Apple's —
/// the ones an indie developer plausibly tracks, plus whatever the user types.
enum Storefront {
    /// (code, label) pairs offered in the picker.
    static let common: [(code: String, name: String)] = [
        ("kr", "대한민국"), ("us", "미국"), ("jp", "일본"), ("gb", "영국"),
        ("de", "독일"), ("fr", "프랑스"), ("ca", "캐나다"), ("au", "호주"),
        ("cn", "중국"), ("tw", "대만"), ("hk", "홍콩"), ("sg", "싱가포르"),
        ("mx", "멕시코"), ("br", "브라질"), ("es", "스페인"), ("it", "이탈리아"),
        ("in", "인도"), ("id", "인도네시아"), ("th", "태국"), ("vn", "베트남"),
    ]

    static func name(for code: String) -> String {
        common.first { $0.code == code }?.name
            ?? Locale.current.localizedString(forRegionCode: code)
            ?? code.uppercased()
    }
}
