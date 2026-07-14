import Foundation

/// Finds a video-conferencing link inside an event's URL, notes, or location
/// so Chronos can show a one-tap "Join" — the little touch Cron and
/// Fantastical are loved for.
enum MeetingLink {
    struct Detected {
        let url: URL
        let platform: String
    }

    /// (host-substring, display name), most specific first.
    private static let providers: [(String, String)] = [
        ("zoom.us", "Zoom"),
        ("meet.google.com", "Google Meet"),
        ("teams.microsoft.com", "Teams"),
        ("teams.live.com", "Teams"),
        ("webex.com", "Webex"),
        ("whereby.com", "Whereby"),
        ("meet.jit.si", "Jitsi"),
        ("chime.aws", "Chime"),
        ("gotomeeting.com", "GoToMeeting"),
        ("bluejeans.com", "BlueJeans"),
        ("around.co", "Around"),
        ("discord.gg", "Discord"),
        ("discord.com", "Discord"),
    ]

    /// Scan the combined text of an event for the first meeting link.
    static func detect(in fields: [String?]) -> Detected? {
        let haystack = fields.compactMap { $0 }.joined(separator: "\n")
        guard !haystack.isEmpty else { return nil }

        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let matches = detector.matches(in: haystack, range: NSRange(haystack.startIndex..., in: haystack))
        for match in matches {
            guard let url = match.url, let host = url.host?.lowercased() else { continue }
            for (needle, name) in providers where host.contains(needle) {
                return Detected(url: url, platform: name)
            }
        }
        return nil
    }
}
