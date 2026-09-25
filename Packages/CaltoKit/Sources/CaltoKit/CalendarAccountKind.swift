import Foundation

/// Mirror of `EKSourceType`, so account logic can be tested without EventKit.
public enum CalendarSourceType: Sendable, Hashable, CaseIterable {
    case local
    case exchange
    case calDAV
    case mobileMe
    case subscribed
    case birthdays
    case unknown
}

/// The kind of account a calendar belongs to, as configured in Apple Calendar.
public enum CalendarAccountKind: String, Sendable, Hashable, CaseIterable, Codable {
    case iCloud
    case google
    case exchange
    case local
    case subscribed
    case birthdays
    /// A CalDAV account that is neither iCloud nor recognizably Google (Fastmail, Nextcloud, Workspace on a custom domain…).
    case otherCalDAV
    case other

    public init(sourceType: CalendarSourceType, sourceTitle: String) {
        switch sourceType {
        case .local: self = .local
        case .exchange: self = .exchange
        case .calDAV: self = Self.calDAVKind(title: sourceTitle)
        case .mobileMe: self = .iCloud
        case .subscribed: self = .subscribed
        case .birthdays: self = .birthdays
        case .unknown: self = .other
        }
    }

    /// iCloud and Google both appear as CalDAV sources; only the source title tells them apart.
    private static func calDAVKind(title: String) -> Self {
        let title = title.trimmingCharacters(in: .whitespaces).lowercased()
        if title == "icloud" {
            return .iCloud
        }
        if title.contains("google") || title.hasSuffix("@gmail.com") || title.hasSuffix("@googlemail.com") {
            return .google
        }
        return .otherCalDAV
    }
}
