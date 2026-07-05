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

// MARK: - RecentRoom

struct RecentRoom: Equatable {
    /// Stored WITHOUT cgv/cgName params — re-wrapped with the current name at rejoin time.
    let joinUrl: String
    let gameId: String
    let roomCode: String

    init(joinUrl: String, gameId: String, roomCode: String) {
        self.joinUrl = joinUrl
        self.gameId = gameId
        self.roomCode = roomCode
    }
}
