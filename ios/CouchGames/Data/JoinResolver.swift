import Foundation

// MARK: - Outcome

enum JoinOutcome: Equatable {
    case success(game: Game, roomCode: String, claim: String?, instance: String?, joinUrl: String)
    case failure(message: String)
}

// MARK: - Resolver

enum JoinResolver {

    /// Turns a scanned QR value or typed string into a join target. Never throws.
    static func resolve(_ raw: String?, games: [Game]) -> JoinOutcome {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .failure(message: String(localized: "Empty code."))
        }

        // Parse failure, or no scheme / no host → bare code path (sole live game).
        guard let components = URLComponents(string: trimmed),
              components.scheme != nil,
              let host = components.host, !host.isEmpty else {
            return soleLiveGameJoin(games: games, roomCode: trimmed, claim: nil, instance: nil)
        }

        // Path segments: split on "/", empties dropped; room code = first segment or "".
        let segments = components.path.split(separator: "/").map(String.init)
        let roomCode = segments.first ?? ""
        let claim = components.queryItems?.first(where: { $0.name == "claim" })?.value
        let instance: String? = components.percentEncodedFragment.map { $0.removingPercentEncoding ?? $0 }

        let lowerHost = host.lowercased()

        // Canonical launcher links: bare domain or www only (exact match, not subdomains).
        if lowerHost == CG.launcherHost || lowerHost == "www." + CG.launcherHost {
            return soleLiveGameJoin(games: games, roomCode: roomCode, claim: claim, instance: instance)
        }

        // A trusted domain IS the controller: always https, port/userinfo dropped.
        let base = "https://" + host

        // Game-domain match: first game whose hosts allow-list covers this host.
        if let game = games.first(where: { g in g.hosts.contains(where: { hostInDomain(host, $0) }) }) {
            return joinAt(base: base, game: game, roomCode: roomCode, claim: claim, instance: instance)
        }

        // couch-games.com subdomain (preview/branch deployments): id-prefix match, else synthetic launcher.
        if hostInDomain(host, CG.launcherHost) {
            let game = games.first(where: { lowerHost.hasPrefix($0.id) }) ?? Game.syntheticLauncher
            return joinAt(base: base, game: game, roomCode: roomCode, claim: claim, instance: instance)
        }

        return .failure(message: String(localized: "That code isn’t a Couch Games room."))
    }

    // MARK: Internals

    private static func soleLiveGameJoin(games: [Game], roomCode: String,
                                         claim: String?, instance: String?) -> JoinOutcome {
        guard let game = games.first(where: { $0.isLive }) else {
            return .failure(message: String(localized: "No live game configured."))
        }
        guard let base = game.controllerBaseUrl else {
            return .failure(message: String(localized: "That game has no controller URL."))
        }
        return joinAt(base: base, game: game, roomCode: roomCode, claim: claim, instance: instance)
    }

    private static func joinAt(base: String, game: Game, roomCode: String,
                               claim: String?, instance: String?) -> JoinOutcome {
        // Validate: exact length and every char in the suite charset (case-sensitive).
        guard roomCode.count == CG.roomCodeLength,
              roomCode.allSatisfy({ CG.base58.contains($0) }) else {
            return .failure(message: String(localized: "That code isn’t a Couch Games room."))
        }

        var stripped = base
        while stripped.hasSuffix("/") { stripped.removeLast() }

        var joinUrl = stripped + "/" + roomCode
        if let claim, !claim.isEmpty {
            joinUrl += "?claim=" + androidUriEncode(claim)
        }
        if let instance, !instance.isEmpty {
            joinUrl += "#" + androidUriEncode(instance)
        }
        return .success(game: game, roomCode: roomCode, claim: claim, instance: instance, joinUrl: joinUrl)
    }
}
