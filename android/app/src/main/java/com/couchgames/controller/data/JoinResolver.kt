package com.couchgames.controller.data

import android.net.Uri
import androidx.annotation.StringRes
import com.couchgames.controller.R

/** The suite's canonical launcher domain (couch-games.com links, display fallback). */
const val LAUNCHER_HOST = "couch-games.com"

/** True when [host] is [domain] itself or any subdomain of it (case-insensitive). */
fun hostInDomain(host: String?, domain: String): Boolean {
  val h = host?.lowercase() ?: return false
  val d = domain.lowercase()
  return h == d || h.endsWith(".$d")
}

sealed interface JoinOutcome {
  data class Success(
    val game: Game,
    val roomCode: String,
    val claim: String?,
    val instance: String?,
    val joinUrl: String,
  ) : JoinOutcome

  data class Failure(@param:StringRes val messageRes: Int) : JoinOutcome
}

/**
 * Resolves a scanned/typed value into a controller join target, grounded in the
 * real payload: https://hexstacker.com/<CODE> (room code = first path segment;
 * optional ?claim and #instance). Never throws.
 *
 * Principle: a trusted domain IS the controller — a scanned URL loads its own
 * origin (staging and preview deployments included), it is never rewritten to
 * another host. The two exceptions carry no origin of their own: bare typed
 * codes and canonical couch-games.com/<code> links (bare domain or www), which
 * resolve to the sole live game's controllerBaseUrl.
 */
object JoinResolver {

  fun resolve(raw: String?, games: List<Game>): JoinOutcome {
    val s = raw?.trim().orEmpty()
    if (s.isEmpty()) return JoinOutcome.Failure(R.string.error_empty_code)

    val uri = runCatching { Uri.parse(s) }.getOrNull()
    val host = uri?.host
    if (uri?.scheme == null || host == null) {
      // Bare code — no origin to load; the sole live game hosts it.
      return soleLiveGameJoin(games, roomCode = s, claim = null, instance = null)
    }

    val segs = uri.pathSegments
    val claim = uri.getQueryParameter("claim")
    val instance = uri.fragment?.let { f -> runCatching { Uri.decode(f) }.getOrDefault(f) }

    // Canonical couch-games.com/<CODE> links (bare domain or www) carry no
    // controller origin of their own, so the sole live game hosts them. The App
    // Links filter claims exactly-6-char paths, so the marketing index never
    // reaches the app; a non-room 6-char path is rejected by validCode.
    // (Subdomains are preview deployments and load their own origin — below.)
    if (host.equals(LAUNCHER_HOST, true) || host.equals("www.$LAUNCHER_HOST", true)) {
      return soleLiveGameJoin(games, segs.firstOrNull().orEmpty(), claim, instance)
    }

    // A game's own domain, or a couch-games.com subdomain (preview/branch
    // deployment). The subdomain prefix names the game when it can ("tinytrack-…"),
    // purely for title/metadata — the URL itself is what gets loaded.
    val game = games.firstOrNull { g -> g.hosts.any { hostInDomain(host, it) } }
      ?: if (hostInDomain(host, LAUNCHER_HOST)) {
        games.firstOrNull { host.lowercase().startsWith(it.id) } ?: launcherGame()
      } else {
        return JoinOutcome.Failure(R.string.error_not_couch_games_room)
      }
    return joinAt("https://$host", game, segs.firstOrNull().orEmpty(), claim, instance)
  }

  private fun soleLiveGameJoin(games: List<Game>, roomCode: String, claim: String?, instance: String?): JoinOutcome {
    val game = games.firstOrNull { it.isLive }
      ?: return JoinOutcome.Failure(R.string.error_no_live_game)
    val base = game.controllerBaseUrl
      ?: return JoinOutcome.Failure(R.string.error_no_controller_url)
    return joinAt(base, game, roomCode, claim, instance)
  }

  private fun joinAt(base: String, game: Game, roomCode: String, claim: String?, instance: String?): JoinOutcome {
    if (!validCode(roomCode)) return JoinOutcome.Failure(R.string.error_not_couch_games_room)
    val joinUrl = buildString {
      append(base.trimEnd('/')).append('/').append(roomCode)
      if (!claim.isNullOrEmpty()) append("?claim=").append(Uri.encode(claim))
      if (!instance.isNullOrEmpty()) append('#').append(Uri.encode(instance))
    }
    return JoinOutcome.Success(game, roomCode, claim, instance, joinUrl)
  }

  // Stand-in metadata for a couch-games.com subdomain that doesn't map to any
  // known game — the deployment is still trusted and loads; only the title and
  // room-code format fall back to suite defaults.
  private fun launcherGame() = Game(
    id = "couch-games",
    name = "Couch Games",
    status = "live",
    accentColor = DefaultAccent,
    art = null,
    controllerBaseUrl = null,
    hosts = emptyList(),
  )

  private fun validCode(code: String): Boolean {
    if (code.length != ROOM_CODE_LENGTH) return false
    return code.all { it in BASE58 }
  }
}
