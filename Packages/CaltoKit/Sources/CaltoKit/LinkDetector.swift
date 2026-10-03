import Foundation

/// Finds links in text the user typed or that was read from a screenshot, so none is lost even when
/// the model forgets one. Web links only (no mail or phone links).
public enum LinkDetector {
    /// Absolute URLs in order of appearance, without duplicates; bare ones ("t.me/c/1/2") get `https://`.
    public static func links(in text: String) -> [String] {
        guard !text.isEmpty, let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        var found: [String] = []
        var seen = Set<String>()
        let range = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, range: range) {
            guard let url = match.url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
                continue
            }
            // The detector adds `http://` to bare links; today's sites are https.
            let written = (text as NSString).substring(with: match.range)
            let link = written.lowercased().hasPrefix("http") ? url.absoluteString : "https://\(written)"
            if seen.insert(key(for: link)).inserted {
                found.append(link)
            }
        }
        return found
    }

    /// Comparison key: the same link written with or without scheme, `www.` or a trailing slash.
    public static func key(for link: String) -> String {
        var value = link.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in ["https://", "http://"] where value.hasPrefix(prefix) {
            value.removeFirst(prefix.count)
        }
        if value.hasPrefix("www.") {
            value.removeFirst(4)
        }
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }
}
