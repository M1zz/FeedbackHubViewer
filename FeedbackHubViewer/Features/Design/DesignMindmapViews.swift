//
//  DesignMindmapViews.swift
//  FeedbackHubViewer
//
//  결제까지 마인드맵 - 앱마다 문제 정의 · 타겟 · 솔루션, 그리고 처음 알게 된 순간부터
//  결제하는 순간까지의 길을 한 장에 펼친 판.
//
//  이 앱 안의 `Mindmaps/mindmap-<프로젝트 키>.html` 하나뿐이다. 원본은
//  `scripts/mindmaps/<프로젝트 키>.json` 이고 `scripts/build-mindmaps.py` 가 HTML 을 만든다.
//  앱에 들어 있으니 폴더 허락 없이도, 폰 · 패드에서도 열린다.
//

import SwiftUI

enum DesignMindmaps {
    static func url(for project: String) -> URL? {
        Bundle.main.url(forResource: "mindmap-\(project)", withExtension: "html")
    }

    /// 앱에 든 마인드맵 전부: 프로젝트 키 → 앱 이름. 허브에 아직 안 잡힌 앱도 여기 있다.
    static let index: [String: String] = {
        guard let url = Bundle.main.url(forResource: "mindmaps", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let index = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return index
    }()
}

/// 한 앱의 결제까지 마인드맵 판정 한 장.
struct DesignMindmapCard: View {
    @EnvironmentObject private var store: FeedbackStore
    let project: String

    var body: some View {
        if let url = DesignMindmaps.url(for: project) {
            Card(title: "결제까지 마인드맵", systemImage: "point.3.connected.trianglepath.dotted") {
                Text("\(store.displayName(for: project))의 문제 정의 · 타겟 · 솔루션과, 처음 알게 된 순간부터 결제하는 순간까지.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                BlueprintOpenButton(title: "마인드맵 열기", source: .bundled(url), prominent: true, sheetTitle: "결제까지 마인드맵")
            }
        } else {
            Card(title: "결제까지 마인드맵 없음", systemImage: "xmark.circle") {
                Text("\(store.displayName(for: project))에는 아직 마인드맵이 없습니다.")
                    .font(.body)
                Text("scripts/mindmaps/\(project).json 을 쓰고 scripts/build-mindmaps.py 를 돌리세요.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

/// 전체 프로젝트: 마인드맵이 있는 앱 전부(허브에 없는 앱까지), 그 뒤에 허브에는 있는데
/// 마인드맵이 없는 앱.
struct DesignMindmapRollCall: View {
    @EnvironmentObject private var store: FeedbackStore

    private struct Row {
        let project: String
        let name: String
        let url: URL?
    }

    var body: some View {
        let rows = self.rows
        let made = rows.filter { $0.url != nil }.count
        Card(title: "결제까지 마인드맵", systemImage: "point.3.connected.trianglepath.dotted") {
            Text("\(rows.count)개 앱 중 \(made)개에 있습니다.")
                .font(.body)
                .foregroundStyle(.secondary)
            ForEach(rows, id: \.project) { row in
                HStack(spacing: 8) {
                    Image(systemName: row.url == nil ? "xmark.circle" : "checkmark.circle.fill")
                        .foregroundStyle(row.url == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.green))
                    Text(row.name)
                        .font(.body)
                    Spacer(minLength: 8)
                    if let url = row.url {
                        BlueprintOpenButton(title: "열기", source: .bundled(url), sheetTitle: "결제까지 마인드맵")
                    } else {
                        Text("없음")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var rows: [Row] {
        let made = DesignMindmaps.index
            .compactMap { project, name in
                DesignMindmaps.url(for: project).map { Row(project: project, name: name, url: $0) }
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let have = Set(made.map(\.project))
        let lacking = store.allProjectKeys
            .filter { $0 != Feedback.unclassifiedProject && !have.contains($0) }
            .map { Row(project: $0, name: store.displayName(for: $0), url: nil) }
        return made + lacking
    }
}
