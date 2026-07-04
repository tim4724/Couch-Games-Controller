import Foundation

// MARK: - ProfileStore

enum ProfileStore {

    private static let nameKey = "cg_profile.name"

    static func load(defaults: UserDefaults = .standard) -> Profile {
        Profile(name: defaults.string(forKey: nameKey) ?? "")
    }

    /// Writes the name verbatim — no trimming on save.
    static func save(_ profile: Profile, defaults: UserDefaults = .standard) {
        defaults.set(profile.name, forKey: nameKey)
    }
}

// MARK: - RecentRoomStore

enum RecentRoomStore {

    static let maxAgeMillis: Int64 = 12 * 60 * 60 * 1000

    private static let joinUrlKey = "cg_recent.joinUrl"
    private static let gameIdKey = "cg_recent.gameId"
    private static let roomCodeKey = "cg_recent.roomCode"
    private static let savedAtKey = "cg_recent.savedAt"

    /// No-op unless the outcome is .success. Single-slot store — overwrites any previous record.
    static func save(_ outcome: JoinOutcome, defaults: UserDefaults = .standard) {
        guard case .success(let game, let roomCode, _, _, let joinUrl) = outcome else { return }
        defaults.set(joinUrl, forKey: joinUrlKey)
        defaults.set(game.id, forKey: gameIdKey)
        defaults.set(roomCode, forKey: roomCodeKey)
        defaults.set(Int(Date().timeIntervalSince1970 * 1000), forKey: savedAtKey)
    }

    /// nil if any of joinUrl/gameId/roomCode is missing, or the record is older than 12 h
    /// (missing savedAt reads as 0 → always expired). Stale records are ignored, not deleted.
    static func load(now: Date = Date(), defaults: UserDefaults = .standard) -> RecentRoom? {
        guard let joinUrl = defaults.string(forKey: joinUrlKey),
              let gameId = defaults.string(forKey: gameIdKey),
              let roomCode = defaults.string(forKey: roomCodeKey) else {
            return nil
        }
        let savedAt = (defaults.object(forKey: savedAtKey) as? NSNumber)?.int64Value ?? 0
        let nowMillis = Int64(now.timeIntervalSince1970 * 1000)
        if nowMillis - savedAt > maxAgeMillis {
            return nil
        }
        return RecentRoom(joinUrl: joinUrl, gameId: gameId, roomCode: roomCode)
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: joinUrlKey)
        defaults.removeObject(forKey: gameIdKey)
        defaults.removeObject(forKey: roomCodeKey)
        defaults.removeObject(forKey: savedAtKey)
    }
}

// MARK: - Profile URL wrapping (contract §7.1)

/// If the profile is set, append cgv=1 then cgName=<androidUriEncode(name)> to the query,
/// preserving any existing query (append with & or ?) and keeping the #fragment at the end.
/// Otherwise the joinUrl is returned unchanged. Pure string manipulation — no URL round-tripping.
func withProfile(_ joinUrl: String, _ profile: Profile) -> String {
    guard profile.isSet else { return joinUrl }

    let base: String
    let fragment: String
    if let hashIndex = joinUrl.firstIndex(of: "#") {
        base = String(joinUrl[..<hashIndex])
        fragment = String(joinUrl[hashIndex...])
    } else {
        base = joinUrl
        fragment = ""
    }

    let separator = base.contains("?") ? "&" : "?"
    return base + separator + "cgv=1&cgName=" + androidUriEncode(profile.name) + fragment
}
