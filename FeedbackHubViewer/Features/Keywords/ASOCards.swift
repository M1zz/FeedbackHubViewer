//
//  ASOCards.swift
//  FeedbackHubViewer
//
//  키워드 화면의 ASO 카드들 — 한 앱을 볼 때만 뜬다.
//
//   순위 추이       — 이미 쌓인 순위 기록으로. 키가 없어도 된다.
//   스토어 메타데이터 — App Store Connect에서 이름 · 부제 · 키워드 · 프로모션 텍스트를
//                    읽어 대조하고, 고칠 수 있으면 고친다.
//   노출 · 전환      — App Store 노출 → 페이지 조회 → 첫 다운로드, 경로별.
//
//  순위는 "어디에 서 있나", 메타데이터는 "무엇을 걸어 뒀나", 노출 · 전환은 "그래서
//  사람이 왔나"다. 셋이 한 화면에 있어야 키워드 하나를 고친 결과를 끝까지 따라간다.
//

import SwiftUI
import Charts

// MARK: - 순위 추이

struct RankTrendCard: View {
    @EnvironmentObject private var keywords: KeywordStore
    let project: String

    @State private var days = 30
    @State private var selection = ChartSeriesSelection()
    @State private var cursor: Date?

    private static let palette: [Color] = [.blue, .orange, .green, .purple, .pink, .teal]

    var body: some View {
        let trackId = keywords.trackId(for: project)
        let alerts = keywords.history.rankAlerts(for: project, trackId: trackId)
        Card(title: "순위 추이", systemImage: "chart.line.uptrend.xyaxis") {
            if let trackId {
                let lines = self.lines(trackId: trackId)
                Picker("기간", selection: $days) {
                    Text("30일").tag(30)
                    Text("90일").tag(90)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if lines.isEmpty {
                    note("아직 순위에 잡힌 키워드가 없습니다.")
                } else {
                    chart(lines)
                    ChartLegend(series: lines.map(\.series), selection: $selection)
                    note("지금 순위가 높은 키워드 \(lines.count)개입니다. 위가 1위예요. 끊긴 곳은 확인을 안 했거나 순위에 없던 날입니다.")
                }

                Divider()
                Text("최근 일주일 사이")
                    .font(.headline)
                if alerts.isEmpty {
                    note("일주일 전과 견줘 \(KeywordHistory.bigMove)계단 넘게 움직인 키워드도, 나를 새로 앞지른 앱도 없습니다.")
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(alerts) { alert in alertRow(alert) }
                    }
                }
            } else {
                note("이 앱이 App Store에 이어지지 않아 순위를 모릅니다.")
            }
        }
    }

    private struct Line {
        let series: ChartSeries
        let points: [(date: Date, rank: Int?)]
    }

    private func lines(trackId: Int) -> [Line] {
        let standings = keywords.standings(for: project).filter(\.isRanked)
            .sorted { ($0.rank ?? .max) < ($1.rank ?? .max) }
            .prefix(Self.palette.count)
        return standings.enumerated().map { index, standing in
            let keyword = standing.keyword
            return Line(series: ChartSeries(keyword.id, "\(keyword.term) (\(keyword.country.uppercased()))",
                                            Self.palette[index]),
                        points: keywords.history.rankSeries(keyword, trackId: trackId, days: days))
        }
    }

    private func chart(_ lines: [Line]) -> some View {
        let visible = lines.filter { selection.isVisible($0.series.id) }
        return Chart {
            ForEach(visible, id: \.series.id) { line in
                ForEach(Array(line.points.enumerated()), id: \.offset) { _, point in
                    if let rank = point.rank {
                        LineMark(x: .value("날짜", point.date, unit: .day),
                                 y: .value("순위", rank),
                                 series: .value("키워드", line.series.label))
                            .foregroundStyle(line.series.color)
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("날짜", point.date, unit: .day), y: .value("순위", rank))
                            .foregroundStyle(line.series.color)
                            .symbolSize(12)
                    }
                }
            }
            if let cursor, let readout = readout(visible, at: cursor) {
                RuleMark(x: .value("날짜", readout.date, unit: .day))
                    .foregroundStyle(Color.secondary.opacity(0.35))
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        ChartReadout(title: AppFormat.chartDay(readout.date), items: readout.items)
                    }
            }
        }
        // 1위가 위에 오도록 뒤집는다.
        .chartYScale(domain: .automatic(includesZero: false, reversed: true))
        .chartYAxis { AxisMarks(position: .leading) }
        .frame(height: 200)
        .chartCursor($cursor)
    }

    private func readout(_ lines: [Line], at cursor: Date) -> (date: Date, items: [ChartReadout.Item])? {
        guard let nearest = lines.first?.points.min(by: {
            abs($0.date.timeIntervalSince(cursor)) < abs($1.date.timeIntervalSince(cursor))
        }) else { return nil }
        let items = lines.map { line -> ChartReadout.Item in
            let rank = line.points.first { Calendar.current.isDate($0.date, inSameDayAs: nearest.date) }?.rank
            return ChartReadout.Item(label: line.series.label, value: rank.map { "\($0)위" } ?? "—",
                                     color: line.series.color)
        }
        return (nearest.date, items)
    }

    private func alertRow(_ alert: RankAlert) -> some View {
        let text: String
        let icon: String
        switch alert.kind {
        case .dropped(let from, let to):
            text = "\(from)위 → \(to)위로 \(to - from)계단 떨어짐"; icon = "arrow.down.circle"
        case .climbed(let from, let to):
            text = "\(from)위 → \(to)위로 \(from - to)계단 오름"; icon = "arrow.up.circle"
        case .lost(let from):
            text = "\(from)위였는데 순위에서 빠짐"; icon = "xmark.circle"
        case .entered(let to):
            text = "새로 잡힘 — \(to)위"; icon = "sparkles"
        case .overtaken(let names, let rank):
            text = "지금 \(rank)위 — 새로 앞지른 앱: " + names.prefix(3).joined(separator: ", ")
                + (names.count > 3 ? " 외 \(names.count - 3)개" : "")
            icon = "person.2.badge.gearshape"
        }
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(alert.kind.isBad ? .orange : .green)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(alert.keyword.term) (\(alert.keyword.country.uppercased()))")
                    .font(.headline)
                Text(text)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(alert.from) → \(alert.to)")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - 스토어 메타데이터

struct StoreMetadataCard: View {
    @EnvironmentObject private var connect: AppStoreConnectStore
    @EnvironmentObject private var keywords: KeywordStore
    let project: String

    @State private var locale: String?
    @State private var isEditing = false

    var body: some View {
        Card(title: "스토어 메타데이터", systemImage: "text.magnifyingglass") {
            if !connect.isConfigured {
                note("App Store Connect 키를 넣으면 이름 · 부제 · 키워드 필드를 읽어 추적 중인 키워드와 대조합니다. \"앱 내 구입\" 섹션에서 넣을 수 있어요.")
            } else {
                switch connect.metadata[project] {
                case nil, .loading?:
                    ProgressView("메타데이터를 읽는 중…").font(.body)
                case .failed(let message)?:
                    Text(message).font(.body).foregroundStyle(.orange)
                    Button("다시 읽기") { Task { await connect.loadMetadata(bundleID: project, force: true) } }
                case .loaded(let metadata)?:
                    content(metadata)
                }
            }
        }
        .task(id: project) { await connect.loadMetadata(bundleID: project) }
        .sheet(isPresented: $isEditing) {
            if let metadata = connect.metadata[project]?.value, let locale = currentLocale(metadata) {
                MetadataEditor(project: project, metadata: metadata, locale: locale) { isEditing = false }
            }
        }
    }

    /// 추적 중인 키워드의 첫 나라에 맞는 로케일이 기본값.
    private func currentLocale(_ metadata: StoreMetadata) -> String? {
        if let locale, metadata.live.locales[locale] != nil { return locale }
        let tracked = keywords.history.keywords(for: project)
        for country in tracked.map(\.country) {
            if let found = MetadataAudit.locale(forStorefront: country, available: metadata.locales) { return found }
        }
        return metadata.locales.contains("ko") ? "ko" : metadata.locales.first
    }

    @ViewBuilder
    private func content(_ metadata: StoreMetadata) -> some View {
        if let selected = currentLocale(metadata), let text = metadata.live.locales[selected] {
            HStack(spacing: 10) {
                Picker("로케일", selection: Binding(get: { selected }, set: { locale = $0 })) {
                    ForEach(metadata.locales, id: \.self) { Text($0).tag($0) }
                }
                .fixedSize()
                Spacer()
                Button {
                    Task { await connect.loadMetadata(bundleID: project, force: true) }
                } label: { Label("다시 읽기", systemImage: "arrow.clockwise") }
                Button { isEditing = true } label: { Label("고치기", systemImage: "pencil") }
                    .buttonStyle(.borderedProminent)
            }
            .font(.body)

            note(editionNote(metadata))

            fieldRow("이름", text.name, limit: StoreMetadata.Limit.name)
            fieldRow("부제", text.subtitle, limit: StoreMetadata.Limit.subtitle)
            fieldRow("키워드", text.keywords, limit: StoreMetadata.Limit.keywords)
            fieldRow("프로모션 텍스트", text.promotionalText, limit: StoreMetadata.Limit.promotionalText)

            Divider()
            auditSection(MetadataAudit.keywordField(text))
            Divider()
            coverageSection(text, locale: selected)
        } else {
            note("이 앱에는 읽을 수 있는 로케일이 없습니다.")
        }
    }

    private func editionNote(_ metadata: StoreMetadata) -> String {
        var text = "지금 스토어에 나가 있는 버전 \(metadata.live.versionString ?? "—") 기준입니다."
        if let draft = metadata.draft {
            text += " 고칠 수 있는 버전 \(draft.versionString ?? "—")이 있어서 키워드 · 이름 · 부제를 고치면 그 버전에 들어가고, 심사를 거쳐 나갑니다."
        } else {
            text += " 고칠 수 있는 버전이 없어서 지금은 프로모션 텍스트만 바로 고칠 수 있어요. 키워드 · 이름 · 부제는 App Store Connect에서 새 버전을 만들면 고쳐집니다."
        }
        return text
    }

    private func fieldRow(_ title: String, _ value: String, limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text("\(value.count)/\(limit)")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(value.count > limit ? .red : .secondary)
            }
            Text(value.isEmpty ? "비어 있음" : value)
                .font(.body)
                .foregroundStyle(value.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func auditSection(_ audit: MetadataAudit.KeywordField) -> some View {
        Text("키워드 필드 점검").font(.headline)
        if audit.isClean {
            Label("버리는 글자가 없습니다. 남은 칸 \(audit.unused)자.", systemImage: "checkmark.circle")
                .font(.body).foregroundStyle(.green)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if audit.wastedSpaces > 0 {
                    issue("쉼표 옆 공백으로 \(audit.wastedSpaces)자를 버리고 있어요. 공백 없이 쉼표로만 이어도 똑같이 잡힙니다.")
                }
                if !audit.alreadyIndexed.isEmpty {
                    issue("이름 · 부제에 이미 있는 단어: " + audit.alreadyIndexed.joined(separator: ", ") + " — 스토어가 세 필드를 한데 모아 읽어서 여기 또 적을 필요가 없어요.")
                }
                if !audit.duplicates.isEmpty {
                    issue("두 번 적은 단어: " + audit.duplicates.joined(separator: ", "))
                }
                Text("정리하면 \(audit.reclaimable)자가 생깁니다(남은 칸 포함 \(audit.reclaimable + audit.unused)자). 그 자리에 아래 \"없음\" 키워드를 넣을 수 있어요.")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                Text(audit.cleaned)
                    .font(.body.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func issue(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.circle")
            .font(.body)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func coverageSection(_ text: StoreMetadata.LocaleText, locale: String) -> some View {
        let standings = keywords.standings(for: project).filter {
            MetadataAudit.locale(forStorefront: $0.keyword.country, available: [locale]) == locale
        }
        Text("추적 중인 키워드가 들어 있는 곳").font(.headline)
        if standings.isEmpty {
            note("이 로케일(\(locale))을 읽는 나라의 추적 키워드가 없습니다.")
        } else {
            let rows = standings.map { ($0, MetadataAudit.coverage(of: $0.keyword.term, in: text)) }
                .sorted { lhs, rhs in
                    // 메타데이터에 없고 순위도 없는 것이 할 일이라 먼저.
                    let l = (lhs.1.isCovered ? 1 : 0, lhs.0.rank ?? 999)
                    let r = (rhs.1.isCovered ? 1 : 0, rhs.0.rank ?? 999)
                    return l < r
                }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(rows, id: \.0.keyword.id) { standing, coverage in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(standing.keyword.term).font(.body.weight(.medium))
                        Text(standing.rank.map { "\($0)위" } ?? "안 잡힘")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Text(coverageLabel(coverage))
                            .font(.body)
                            .foregroundStyle(coverage.isCovered ? .green : (coverage.isPartial ? .yellow : .orange))
                    }
                }
            }
            let missing = rows.filter { !$0.1.isCovered }
            if !missing.isEmpty {
                note("메타데이터에 없는 키워드 \(missing.count)개는 그 단어로 검색해도 앱이 잡힐 근거가 약합니다. 순위가 있어도 리뷰나 다른 신호로 잡힌 것이라 오래 버티기 어려워요.")
            }
        }
    }

    private func coverageLabel(_ coverage: MetadataAudit.Coverage) -> String {
        if coverage.isCovered { return coverage.fields.map(\.rawValue).joined(separator: " · ") }
        if coverage.isPartial { return "일부 — 없는 단어: " + coverage.missingWords.joined(separator: ", ") }
        return "없음"
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - 메타데이터 고치기

/// 고칠 값을 적고, 바뀌는 것을 한 번 더 보여 준 뒤에 저장한다. 저장은 곧 스토어다 —
/// 프로모션 텍스트는 심사 없이 바로 나가고, 나머지는 다음 버전 심사에 들어간다.
private struct MetadataEditor: View {
    @EnvironmentObject private var connect: AppStoreConnectStore
    let project: String
    let metadata: StoreMetadata
    let locale: String
    let onClose: () -> Void

    @State private var name = ""
    @State private var subtitle = ""
    @State private var keywordsText = ""
    @State private var promo = ""
    @State private var isReviewing = false
    @State private var isSaving = false
    @State private var error: String?

    private var live: StoreMetadata.LocaleText? { metadata.live.locales[locale] }
    /// 이름 · 부제 · 키워드의 기준 — 고칠 수 있는 버전이 있으면 그것.
    private var base: StoreMetadata.LocaleText? { metadata.draft?.locales[locale] ?? live }
    private var canEditInfo: Bool { metadata.draft?.isAppInfoEditable == true && base?.appInfoLocalizationID != nil }
    private var canEditKeywords: Bool { metadata.draft?.isVersionEditable == true && base?.versionLocalizationID != nil }
    private var canEditPromo: Bool { live?.versionLocalizationID != nil }

    private var edit: MetadataEdit {
        var edit = MetadataEdit(locale: locale)
        if canEditInfo, name != base?.name { edit.name = name }
        if canEditInfo, subtitle != base?.subtitle { edit.subtitle = subtitle }
        if canEditKeywords, keywordsText != base?.keywords { edit.keywords = keywordsText }
        if canEditPromo, promo != live?.promotionalText { edit.promotionalText = promo }
        return edit
    }

    private var overLimit: Bool {
        name.count > StoreMetadata.Limit.name || subtitle.count > StoreMetadata.Limit.subtitle
            || keywordsText.count > StoreMetadata.Limit.keywords || promo.count > StoreMetadata.Limit.promotionalText
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if isReviewing { review } else { form }
                    if let error {
                        Text(error).font(.body).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding()
            }
            .navigationTitle("메타데이터 고치기 · \(locale)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기", action: onClose)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isReviewing {
                        Button(isSaving ? "저장 중…" : "App Store Connect에 저장") { save() }
                            .disabled(isSaving)
                    } else {
                        Button("바뀌는 것 보기") { isReviewing = true }
                            .disabled(edit.isEmpty || overLimit)
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 600)
        #endif
        .onAppear {
            name = base?.name ?? ""
            subtitle = base?.subtitle ?? ""
            keywordsText = base?.keywords ?? ""
            promo = live?.promotionalText ?? ""
        }
    }

    @ViewBuilder
    private var form: some View {
        field("이름", text: $name, limit: StoreMetadata.Limit.name, enabled: canEditInfo,
              reason: "이름은 고칠 수 있는 앱 정보가 있을 때만 고쳐집니다(새 버전을 만들면 생겨요).")
        field("부제", text: $subtitle, limit: StoreMetadata.Limit.subtitle, enabled: canEditInfo,
              reason: "부제는 고칠 수 있는 앱 정보가 있을 때만 고쳐집니다.")
        field("키워드", text: $keywordsText, limit: StoreMetadata.Limit.keywords, enabled: canEditKeywords,
              reason: "키워드는 제출 전 버전에서만 고쳐집니다. App Store Connect에서 새 버전을 만들어 주세요.",
              multiline: true)
        if canEditKeywords, let base {
            let cleaned = MetadataAudit.keywordField(StoreMetadata.LocaleText(
                locale: locale, name: name, subtitle: subtitle, keywords: keywordsText)).cleaned
            if cleaned != keywordsText {
                Button("공백 · 중복 · 이름에 있는 단어 걷어내기 (\(keywordsText.count - cleaned.count)자 확보)") {
                    keywordsText = cleaned
                }
                .font(.body)
                .help("\(base.keywords.count)자 → \(cleaned.count)자")
            }
        }
        field("프로모션 텍스트", text: $promo, limit: StoreMetadata.Limit.promotionalText, enabled: canEditPromo,
              reason: "이 로케일에 버전 정보가 없습니다.", multiline: true)
        Text("프로모션 텍스트는 검색에 안 잡히지만 심사 없이 바로 바뀝니다. 나머지는 다음 버전 심사를 거쳐 나가요.")
            .font(.body).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var review: some View {
        Text("아래 값이 App Store Connect에 저장됩니다.").font(.headline)
        let edit = self.edit
        if let value = edit.name { change("이름", base?.name ?? "", value) }
        if let value = edit.subtitle { change("부제", base?.subtitle ?? "", value) }
        if let value = edit.keywords { change("키워드", base?.keywords ?? "", value) }
        if let value = edit.promotionalText { change("프로모션 텍스트 (바로 나감)", live?.promotionalText ?? "", value) }
        Button("다시 고치기") { isReviewing = false }
            .font(.body)
    }

    private func change(_ title: String, _ old: String, _ new: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text("전: " + (old.isEmpty ? "(비어 있음)" : old))
                .font(.body).foregroundStyle(.secondary)
                .strikethrough()
                .fixedSize(horizontal: false, vertical: true)
            Text("후: " + (new.isEmpty ? "(비어 있음)" : new))
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: 10, bordered: false)
    }

    private func field(_ title: String, text: Binding<String>, limit: Int, enabled: Bool,
                       reason: String, multiline: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text("\(text.wrappedValue.count)/\(limit)")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(text.wrappedValue.count > limit ? .red : .secondary)
            }
            if multiline {
                TextEditor(text: text)
                    .font(.body)
                    .frame(minHeight: 70)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
                    .disabled(!enabled)
                    .opacity(enabled ? 1 : 0.5)
            } else {
                TextField(title, text: text)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
                    .disabled(!enabled)
            }
            if !enabled {
                Text(reason).font(.body).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func save() {
        isSaving = true
        error = nil
        Task {
            do {
                try await connect.saveMetadata(bundleID: project, edit: edit)
                isSaving = false
                onClose()
            } catch {
                isSaving = false
                self.error = error.localizedDescription
            }
        }
    }
}

// MARK: - 노출 · 전환

struct StoreFunnelCard: View {
    @EnvironmentObject private var connect: AppStoreConnectStore
    let project: String

    @State private var selection = ChartSeriesSelection()
    @State private var cursor: Date?
    @State private var isRequesting = false

    private static let series = [
        ChartSeries("impressions", "검색 노출", .blue),
        ChartSeries("downloads", "첫 다운로드", .green)
    ]

    var body: some View {
        Card(title: "App Store 노출 · 전환 (최근 \(AppStoreConnectStore.salesDays)일)", systemImage: "eye") {
            if !connect.isConfigured {
                note("App Store Connect 키를 넣으면 검색 노출 → 페이지 조회 → 첫 다운로드를 경로별로 보여 줍니다.")
            } else {
                switch connect.funnels[project] {
                case nil, .loading?:
                    ProgressView("노출 · 다운로드 리포트를 받는 중… (30~60초)").font(.body)
                case .failed(let message)?:
                    Text(message).font(.body).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("다시 받기") { Task { await connect.loadFunnel(bundleID: project, force: true) } }
                case .loaded(.noRequest)?:
                    note("이 앱은 아직 App Store 분석 리포트를 요청하지 않았습니다. 요청하면 1~2일 뒤부터 하루치씩 쌓여요. 요청은 한 번이면 되고, 스토어에 보이는 것은 아무것도 바뀌지 않습니다.")
                    Button(isRequesting ? "요청 중…" : "리포트 요청 만들기") {
                        isRequesting = true
                        Task { await connect.requestAnalytics(bundleID: project); isRequesting = false }
                    }
                    .disabled(isRequesting)
                case .loaded(.ready(let funnel))?:
                    content(funnel)
                }
            }
        }
        .task(id: project) { await connect.loadFunnel(bundleID: project) }
    }

    @ViewBuilder
    private func content(_ funnel: StoreFunnel) -> some View {
        if funnel.instances == 0 {
            note("리포트 요청은 있지만 아직 만들어진 파일이 없습니다. 요청하고 1~2일 뒤부터 나와요.")
        } else {
            let total = funnel.total
            HStack(spacing: 16) {
                Figure("노출 (기기)", AppFormat.count(total.impressions))
                Figure("페이지 조회", AppFormat.count(total.pageViews))
                Figure("첫 다운로드", AppFormat.count(total.firstDownloads))
                Figure("전환율", total.conversion.map { String(format: "%.1f%%", $0 * 100) } ?? "—",
                       note: "첫 다운로드 ÷ 노출")
            }

            let sources = funnel.sources.sorted { $0.value.firstDownloads > $1.value.firstDownloads }
            let peak = sources.map(\.value.firstDownloads).max() ?? 0
            VStack(spacing: 10) {
                ForEach(sources, id: \.key) { source, counts in
                    SpecBar(label: StoreFunnel.label(forSource: source),
                            value: "\(AppFormat.count(counts.firstDownloads))회",
                            ratio: peak > 0 ? Double(counts.firstDownloads) / Double(peak) : 0,
                            hint: sourceHint(counts))
                }
            }

            chart(funnel)
            ChartLegend(series: Self.series, selection: $selection)

            note("노출과 페이지 조회는 고유 기기 수, 첫 다운로드는 건수입니다. 다른 앱 · 웹에서 온 사람은 노출 없이 바로 페이지로 들어와서 노출이 0이에요. 검색 전환율이 키워드 작업의 성적표입니다 — 검색에서 보인 사람 중 몇이 받았나. 리포트는 하루 이틀 늦게 나오고, 같은 날짜가 두 파일에 겹쳐 오는 것은 한 번만 셉니다.")
        }
    }

    private func sourceHint(_ counts: StoreFunnel.Counts) -> String {
        var parts: [String] = []
        if counts.impressions > 0 { parts.append("노출 \(AppFormat.count(counts.impressions))") }
        if counts.pageViews > 0 { parts.append("페이지 조회 \(AppFormat.count(counts.pageViews))") }
        if let conversion = counts.conversion { parts.append(String(format: "전환 %.1f%%", conversion * 100)) }
        return parts.joined(separator: " · ")
    }

    private struct DayPoint: Identifiable {
        var id: Date { date }
        let date: Date
        let impressions: Int
        let downloads: Int
    }

    private func chart(_ funnel: StoreFunnel) -> some View {
        let points = funnel.daily.compactMap { key, counts in
            KeywordHistory.date(fromDayKey: key).map {
                DayPoint(date: $0, impressions: counts.impressions, downloads: counts.firstDownloads)
            }
        }.sorted { $0.date < $1.date }
        let showImpressions = selection.isVisible("impressions")
        let showDownloads = selection.isVisible("downloads")
        let peak = points.reduce(0) { max($0, max(showImpressions ? $1.impressions : 0, showDownloads ? $1.downloads : 0)) }
        let nearest = cursor.flatMap { cursor in
            points.min { abs($0.date.timeIntervalSince(cursor)) < abs($1.date.timeIntervalSince(cursor)) }
        }
        return Chart {
            if showImpressions {
                ForEach(points) { point in
                    LineMark(x: .value("날짜", point.date, unit: .day), y: .value("수", point.impressions),
                             series: .value("계열", "검색 노출"))
                        .foregroundStyle(Color.blue)
                        .interpolationMethod(.monotone)
                }
            }
            if showDownloads {
                ForEach(points) { point in
                    LineMark(x: .value("날짜", point.date, unit: .day), y: .value("수", point.downloads),
                             series: .value("계열", "첫 다운로드"))
                        .foregroundStyle(Color.green)
                        .interpolationMethod(.monotone)
                }
            }
            if let nearest {
                RuleMark(x: .value("날짜", nearest.date, unit: .day))
                    .foregroundStyle(Color.secondary.opacity(0.35))
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        ChartReadout(title: AppFormat.chartDay(nearest.date), items: [
                            .init(label: "검색 노출", value: AppFormat.count(nearest.impressions), color: .blue),
                            .init(label: "첫 다운로드", value: AppFormat.count(nearest.downloads), color: .green)
                        ])
                    }
            }
        }
        .chartYScale(domain: 0...Double(max(1, peak)))
        .chartYAxis { AxisMarks(position: .leading) }
        .frame(height: 180)
        .chartCursor($cursor)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
