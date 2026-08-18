//
//  FeedbackTriage.swift
//  FeedbackHubViewer
//
//  What was decided about a piece of feedback: 반영함 / 반영 안 함, plus an
//  optional memo saying why or where it landed.
//
//  The decision lives on the device (UserDefaults, see `FeedbackStore`), not in
//  CloudKit: the hub's records belong to the apps that wrote them and this
//  viewer only holds read access to that public database. Marking feedback here
//  never touches the record — it is this reviewer's own triage log.
//

import SwiftUI

/// The reviewer's verdict on one feedback record.
enum FeedbackStatus: String, Codable, CaseIterable, Identifiable {
    /// Nothing decided yet. The default; never stored.
    case pending
    /// Acted on — the request landed in the product.
    case applied
    /// Consciously not acted on (duplicate, out of scope, spam).
    case dismissed

    var id: String { rawValue }

    /// Handled means "off the desk", whichever way it went.
    var isHandled: Bool { self != .pending }

    var label: String {
        switch self {
        case .pending: return "확인 필요"
        case .applied: return "반영함"
        case .dismissed: return "반영 안 함"
        }
    }

    /// What the button that *moves* feedback into this state says.
    var actionLabel: String {
        switch self {
        case .pending: return "확인 필요로 되돌리기"
        case .applied: return "반영함으로 표시"
        case .dismissed: return "반영 안 함으로 표시"
        }
    }

    var systemImage: String {
        switch self {
        case .pending: return "circle.dashed"
        case .applied: return "checkmark.circle.fill"
        case .dismissed: return "xmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .pending: return .orange
        case .applied: return .green
        case .dismissed: return .secondary
        }
    }
}

/// One record's triage decision as stored on disk.
struct FeedbackTriageEntry: Codable, Hashable {
    var status: FeedbackStatus
    /// Free-form memo — "v1.4에 반영", "중복 피드백" 같은 메모.
    var note: String
    /// When the decision was last changed, shown in the detail view.
    var decidedAt: Date

    /// An entry that carries neither a decision nor a memo is not worth keeping.
    var isEmpty: Bool {
        status == .pending && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Which decisions the feedback list shows. `pending` is the default: once a
/// piece of feedback is decided it leaves the list, and the "처리한 피드백 보기"
/// switch at the bottom brings it back.
///
/// Raw values are stable identifiers, not labels — the choice is persisted.
enum FeedbackStatusFilter: String, CaseIterable, Identifiable {
    case pending
    case handled
    case applied
    case dismissed
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pending: return "확인 필요"
        case .handled: return "처리 완료"
        case .applied: return FeedbackStatus.applied.label
        case .dismissed: return FeedbackStatus.dismissed.label
        case .all: return "전체"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "tray.full"
        case .pending: return FeedbackStatus.pending.systemImage
        case .handled: return "checkmark.circle"
        case .applied: return FeedbackStatus.applied.systemImage
        case .dismissed: return FeedbackStatus.dismissed.systemImage
        }
    }

    func accepts(_ status: FeedbackStatus) -> Bool {
        switch self {
        case .all: return true
        case .pending: return status == .pending
        case .handled: return status.isHandled
        case .applied: return status == .applied
        case .dismissed: return status == .dismissed
        }
    }
}

/// The small status chip shown on list rows and cards. Nothing is drawn for
/// `pending`, so untouched rows stay as clean as they were.
struct StatusChip: View {
    let status: FeedbackStatus
    var showsLabel = true

    var body: some View {
        if status.isHandled {
            HStack(spacing: 3) {
                Image(systemName: status.systemImage)
                if showsLabel {
                    Text(status.label)
                }
            }
            .font(.caption2.weight(.medium))
            .fixedSize()
            .padding(.horizontal, showsLabel ? 6 : 3)
            .padding(.vertical, 2)
            .background(status.tint.opacity(0.15), in: Capsule())
            .foregroundStyle(status.tint)
            .accessibilityLabel(status.label)
        }
    }
}

/// A red-free count capsule for feedback still waiting on a decision.
struct PendingBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.caption2.bold().monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange, in: Capsule())
            .accessibilityLabel("확인 필요 \(count)건")
    }
}
