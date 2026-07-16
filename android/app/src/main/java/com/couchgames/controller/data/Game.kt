package com.couchgames.controller.data

import android.content.Context
import androidx.compose.ui.graphics.Color
import androidx.core.net.toUri
import org.json.JSONObject

// Room codes are minted by the shared relay, so the format is suite-wide, not
// per game: Base58 (case-SENSITIVE, excludes 0 O I l), six characters.
const val BASE58 = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
const val ROOM_CODE_LENGTH = 6

/** Suite indigo — the accent for games with no (valid) accentColor of their own. */
val DefaultAccent = Color(0xFF6C5CE7)

/** One game from games-manifest.json (carousel + scan-resolution source). */
data class Game(
  val id: String,
  val name: String,
  val status: String,            // "live" | "soon"
  val players: String? = null,   // display copy, e.g. "1–8 players"
  val video: String? = null,     // https URL of a muted gameplay loop, cached on demand (TrailerCache)
  val accentColor: Color,
  val art: String?,              // asset-relative path, e.g. "artwork/hexstacker-16x9.webp"
  val controllerBaseUrl: String?,
  val hosts: List<String>,       // domains that resolve to this game (subdomains included)
  // The game's own relay (pre-unification) — where its rooms actually live, so
  // room-alive probes go here rather than the shared directory.
  val relayProbeBase: String? = null,
) {
  val isLive: Boolean get() = status == "live"

  /** Where this game's rooms live: its own relay, else the shared one. */
  val roomRelayBase: String get() = relayProbeBase ?: RELAY_BASE

  /**
   * Host to SHOW users, from the canonical controller URL — [hosts] is the
   * security allow-list, whose ordering must not become display copy.
   */
  val displayHost: String? get() = controllerBaseUrl?.let { runCatching { it.toUri().host }.getOrNull() }
}

/** Manifest parsing — shared by the bundled seed and the served copy (ManifestStore). */
object GamesManifest {
  /**
   * Parses manifest [text]. All-or-nothing: any structural failure or an empty
   * games list → null, so a bad fetch can never half-apply over a good list.
   * There is no in-band schema version — the latest served JSON is the truth,
   * and a breaking rework (if ever) ships under a new manifest URL.
   */
  fun parse(text: String, context: Context): List<Game>? = runCatching {
    val games = JSONObject(text).getJSONArray("games")
    if (games.length() == 0) return@runCatching null
    (0 until games.length()).map { i ->
      val g = games.getJSONObject(i)
      val id = g.getString("id")
      val hostsArr = g.optJSONArray("hosts")
      Game(
        id = id,
        name = g.getString("name"),
        status = g.optString("status", "soon"),
        // Per-game display copy lives in string resources, keyed by game id.
        players = context.optStringByName("game_${id}_players"),
        video = g.optHttpsUrl("video"),
        accentColor = parseHexColor(g.optString("accentColor", "")),
        art = g.optNonBlank("art")?.removePrefix("/"),
        controllerBaseUrl = g.optHttpsUrl("controllerBaseUrl"),
        hosts = if (hostsArr != null) (0 until hostsArr.length()).map { hostsArr.getString(it) } else emptyList(),
        relayProbeBase = g.optHttpsUrl("relayProbeBase")?.trimEnd('/'),
      )
    }
  }.getOrNull()

  /** The manifest shipped in assets — the seed every install can fall back to. Never throws. */
  fun loadBundled(context: Context): List<Game> = runCatching {
    context.assets.open("games-manifest.json").bufferedReader().use { it.readText() }
  }.getOrNull()?.let { parse(it, context) } ?: emptyList()
}

/**
 * Absolute https URL for a manifest art path: site-relative paths (the leading "/"
 * is already stripped at parse) resolve against the launcher host; absolute URLs
 * must be https or they're refused.
 */
fun remoteArtUrl(art: String): String? = when {
  art.startsWith("https://") -> art
  "://" in art -> null
  else -> "https://$LAUNCHER_HOST/$art"
}

private fun JSONObject.optNonBlank(name: String): String? = optString(name, "").ifBlank { null }

/**
 * The manifest may arrive over the network, and its URLs get loaded / probed —
 * https only, one policy for every URL field.
 */
private fun JSONObject.optHttpsUrl(name: String): String? =
  optNonBlank(name)?.takeIf { it.startsWith("https://") }

/** Resolves a string resource by name (e.g. "game_hexstacker_players"); null if absent or blank. */
private fun Context.optStringByName(name: String): String? {
  val resId = resources.getIdentifier(name, "string", packageName)
  return if (resId != 0) getString(resId).ifBlank { null } else null
}

fun parseHexColor(hex: String): Color = runCatching {
  val c = hex.removePrefix("#")
  if (c.length >= 6) Color(c.substring(0, 2).toInt(16), c.substring(2, 4).toInt(16), c.substring(4, 6).toInt(16))
  else DefaultAccent
}.getOrElse { DefaultAccent }
