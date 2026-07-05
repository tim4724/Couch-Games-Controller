import SwiftUI
import Foundation

// MARK: - Global constants

enum CG {
    /// Room codes are minted by the shared relay, so the format is suite-wide, not
    /// per game: Base58 (case-sensitive, excludes 0 O I l), six characters.
    static let base58 = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
    static let roomCodeLength = 6
    /// Fallback accent ("suite indigo") for missing/invalid accent colors and the synthetic launcher.
    static let defaultAccent = Color(cgHex: 0x6C5CE7)
    /// Shared relay for all games; doubles as the room -> controller directory. No trailing slash.
    static let relayBase = "https://ws.couch-games.com"
    /// Canonical launcher domain.
    static let launcherHost = "couch-games.com"
    /// Hosted legal pages, shown in-app via WebDocScreen so they stay reachable from
    /// within the app (§5 DDG imprint requirement; GDPR privacy notice).
    static let privacyURL = "https://couch-games.com/privacy"
    static let imprintURL = "https://couch-games.com/imprint"
    /// Public marketing site. Opened in the system browser from About — a full site,
    /// not an in-app legal doc.
    static let websiteURL = "https://couch-games.com"

    /// Marketing version (CFBundleShortVersionString), surfaced read-only in the
    /// About footer for support/bug reports.
    static var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "" }

    /// The two legal pages cross-link to each other, so the in-app viewer can move
    /// from one to the other. Matches a loaded URL back to a document title (localized)
    /// so the nav bar shows the right one as the page changes; `nil` if unrecognized.
    static func legalTitle(for url: URL?) -> String? {
        let path = (url?.path ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.hasSuffix("imprint") { return String(localized: "Impressum") }
        if path.hasSuffix("privacy") { return String(localized: "Privacy Policy") }
        return nil
    }
}

// MARK: - Game

struct Game: Identifiable, Hashable {
    let id: String
    let name: String
    let status: String
    let players: String?
    let video: String?
    let accentColor: Color
    let art: String?
    let controllerBaseUrl: String?
    let hosts: [String]
    let relayProbeBase: String?

    init(id: String, name: String, status: String = "soon",
         players: String? = nil, video: String? = nil, accentColor: Color = CG.defaultAccent,
         art: String? = nil, controllerBaseUrl: String? = nil, hosts: [String] = [],
         relayProbeBase: String? = nil) {
        self.id = id
        self.name = name
        self.status = status
        self.players = players
        self.video = video
        self.accentColor = accentColor
        self.art = art
        self.controllerBaseUrl = controllerBaseUrl
        self.hosts = hosts
        self.relayProbeBase = relayProbeBase
    }

    /// Exact, case-sensitive comparison against "live".
    var isLive: Bool { status == "live" }

    /// Where this game's rooms live.
    var roomRelayBase: String { relayProbeBase ?? CG.relayBase }

    /// The host component of controllerBaseUrl — what's shown to users as the game's domain.
    var displayHost: String? { controllerBaseUrl.flatMap { URL(string: $0)?.host } }

    /// Used only for unknown couch-games.com subdomains.
    static let syntheticLauncher = Game(id: "couch-games", name: "Couch Games", status: "live")
}

// MARK: - Manifest loading

enum GamesManifest {

    private struct ParseError: Error {}

    /// Loads "games-manifest.json" from the bundle. All-or-nothing: ANY failure → [].
    static func load(bundle: Bundle = .main) -> [Game] {
        do {
            guard let url = bundle.url(forResource: "games-manifest", withExtension: "json") else {
                return []
            }
            let data = try Data(contentsOf: url)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let entries = root["games"] as? [Any] else {
                return []
            }
            return try entries.map { try parseGame($0, bundle: bundle) }
        } catch {
            return []
        }
    }

    private static func parseGame(_ raw: Any, bundle: Bundle) throws -> Game {
        guard let obj = raw as? [String: Any],
              let id = obj["id"] as? String,
              let name = obj["name"] as? String else {
            throw ParseError()
        }

        let status = (obj["status"] as? String) ?? "soon"
        // Per-game display copy lives in string resources, keyed by game id.
        let players = localizedByKey("game_\(id)_players", bundle: bundle)
        let video = blankToNil(obj["video"])
        let accentColor = parseHexColor((obj["accentColor"] as? String) ?? "")

        var art = blankToNil(obj["art"])
        if let a = art, a.hasPrefix("/") {
            art = String(a.dropFirst())
        }

        let controllerBaseUrl = blankToNil(obj["controllerBaseUrl"])

        var relayProbeBase = blankToNil(obj["relayProbeBase"])
        if let r = relayProbeBase {
            var stripped = r
            while stripped.hasSuffix("/") { stripped.removeLast() }
            relayProbeBase = stripped
        }

        let hosts = (obj["hosts"] as? [Any])?.compactMap { $0 as? String } ?? []

        return Game(id: id, name: name, status: status,
                    players: players, video: video, accentColor: accentColor,
                    art: art, controllerBaseUrl: controllerBaseUrl, hosts: hosts,
                    relayProbeBase: relayProbeBase)
    }

    /// Resolves a string resource by key (e.g. "game_hexstacker_players"); nil if absent or blank.
    private static func localizedByKey(_ key: String, bundle: Bundle) -> String? {
        let sentinel = "\u{0}"
        let value = bundle.localizedString(forKey: key, value: sentinel, table: nil)
        return value == sentinel ? nil : blankToNil(value)
    }

    /// Absent, non-string, empty, or whitespace-only → nil.
    private static func blankToNil(_ value: Any?) -> String? {
        guard let s = value as? String,
              !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return s
    }
}

// MARK: - Parsing / matching helpers

/// Strip one leading "#", parse first 6 chars as RRGGBB; length < 6 or invalid pair → CG.defaultAccent. Never throws.
func parseHexColor(_ s: String) -> Color {
    var hex = Substring(s)
    if hex.hasPrefix("#") { hex = hex.dropFirst() }
    guard hex.count >= 6 else { return CG.defaultAccent }
    let chars = Array(hex.prefix(6))
    var value: UInt32 = 0
    for i in 0..<3 {
        let pair = String(chars[i * 2 ... i * 2 + 1])
        guard let byte = UInt8(pair, radix: 16) else { return CG.defaultAccent }
        value = (value << 8) | UInt32(byte)
    }
    return Color(cgHex: value)
}

/// Case-insensitive: host == domain || host ends with "." + domain. nil host → false.
func hostInDomain(_ host: String?, _ domain: String) -> Bool {
    guard let host else { return false }
    let h = host.lowercased()
    let d = domain.lowercased()
    return h == d || h.hasSuffix("." + d)
}

/// Android Uri.encode semantics: percent-encode (UTF-8) everything EXCEPT A–Z a–z 0–9 _ - ! . ~ ' ( ) *
func androidUriEncode(_ s: String) -> String {
    var out = ""
    for byte in Array(s.utf8) {
        switch byte {
        case UInt8(ascii: "A")...UInt8(ascii: "Z"),
             UInt8(ascii: "a")...UInt8(ascii: "z"),
             UInt8(ascii: "0")...UInt8(ascii: "9"),
             UInt8(ascii: "_"), UInt8(ascii: "-"), UInt8(ascii: "!"),
             UInt8(ascii: "."), UInt8(ascii: "~"), UInt8(ascii: "'"),
             UInt8(ascii: "("), UInt8(ascii: ")"), UInt8(ascii: "*"):
            out.append(Character(UnicodeScalar(byte)))
        default:
            out += String(format: "%%%02X", byte)
        }
    }
    return out
}

// MARK: - Profile

struct Profile: Equatable {
    var name: String = ""

    /// Non-blank after trimming whitespace.
    var isSet: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    init(name: String = "") {
        self.name = name
    }
}

// MARK: - FunnyName

/// Wholesome-funny fallback identity. Every device gets a random "Adjective Noun"
/// handle on first launch (see `ProfileStore.load`) so players jump straight into a
/// game instead of hitting a name wall — they can still rename or reroll (the 🎲 in
/// ProfileSheet). English-only by design (v1): gamer tags read as English across all
/// our locales, and it sidesteps a per-culture review of 500+ combos. Every word is
/// ≤7 chars so "Adjective Noun" always fits Contract v1's 16-char cgName. Keep this
/// list in sync with the Android FunnyName in Profile.kt.
enum FunnyName {
    private static let adjectives = [
        "Sneaky", "Turbo", "Wobbly", "Grumpy", "Sleepy", "Sparkly",
        "Chunky", "Zesty", "Feral", "Mighty", "Salty", "Cosmic",
        "Fluffy", "Rowdy", "Spicy", "Jolly", "Bouncy", "Cheeky",
        "Groovy", "Snazzy", "Wacky", "Zippy", "Plucky", "Silly",
    ]
    private static let nouns = [
        "Otter", "Pigeon", "Waffle", "Noodle", "Muffin", "Goblin",
        "Wizard", "Llama", "Gecko", "Taco", "Yeti", "Panda",
        "Nugget", "Pickle", "Walrus", "Cactus", "Toaster", "Raccoon",
        "Narwhal", "Penguin", "Hamster", "Biscuit", "Wombat", "Falcon",
    ]

    /// e.g. "Grumpy Waffle". Always non-blank and ≤16 chars.
    static func random() -> String {
        "\(adjectives.randomElement()!) \(nouns.randomElement()!)"
    }
}

// RecentRoom (and its single-slot in-memory store) live in Stores.swift.
