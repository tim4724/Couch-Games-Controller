package com.couchgames.controller.data

import android.content.Context
import android.net.Uri
import androidx.compose.ui.graphics.Color
import org.json.JSONObject

// Base58, case-SENSITIVE (excludes 0 O I l) — the HexStacker room-code charset.
const val BASE58 = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

/** Suite indigo — the accent for games with no (valid) accentColor of their own. */
val DefaultAccent = Color(0xFF6C5CE7)

/** One game from games-manifest.json (carousel + scan-resolution source). */
data class Game(
  val id: String,
  val name: String,
  val status: String,            // "live" | "soon"
  val tagline: String,
  val players: String? = null,   // display copy, e.g. "1–8 players"
  val video: String? = null,     // res/raw resource name of a muted gameplay loop
  val accentColor: Color,
  val art: String?,              // asset-relative path, e.g. "artwork/hexstacker-16x9.webp"
  val controllerBaseUrl: String?,
  val hosts: List<String>,       // domains that resolve to this game (subdomains included)
  val roomCodeCharset: String,
  val roomCodeLength: Int,
  // The game's own relay (pre-unification) — where its rooms actually live, so
  // room-alive probes go here rather than the shared directory.
  val relayProbeBase: String? = null,
  // Optional per-game copy for not-yet-live titles.
  val comingSoonNote: String? = null,
) {
  val isLive: Boolean get() = status == "live"

  /** Where this game's rooms live: its own relay, else the shared one. */
  val roomRelayBase: String get() = relayProbeBase ?: RELAY_BASE

  /**
   * Host to SHOW users, from the canonical controller URL — [hosts] is the
   * security allow-list, whose ordering must not become display copy.
   */
  val displayHost: String? get() = controllerBaseUrl?.let { runCatching { Uri.parse(it).host }.getOrNull() }
}

/** Loads the bundled manifest from assets. Never throws — returns [] on failure. */
object GamesManifest {
  fun load(context: Context): List<Game> = runCatching {
    val text = context.assets.open("games-manifest.json").bufferedReader().use { it.readText() }
    val games = JSONObject(text).getJSONArray("games")
    (0 until games.length()).map { i ->
      val g = games.getJSONObject(i)
      val fmt = g.optJSONObject("roomCodeFormat")
      val hostsArr = g.optJSONArray("hosts")
      Game(
        id = g.getString("id"),
        name = g.getString("name"),
        status = g.optString("status", "soon"),
        tagline = g.optString("tagline", ""),
        players = g.optNonBlank("players"),
        video = g.optNonBlank("video"),
        accentColor = parseHexColor(g.optString("accentColor", "")),
        art = g.optNonBlank("art")?.removePrefix("/"),
        controllerBaseUrl = g.optNonBlank("controllerBaseUrl"),
        hosts = if (hostsArr != null) (0 until hostsArr.length()).map { hostsArr.getString(it) } else emptyList(),
        roomCodeCharset = fmt?.optNonBlank("charset") ?: BASE58,
        roomCodeLength = fmt?.optInt("length", 6) ?: 6,
        relayProbeBase = g.optNonBlank("relayProbeBase")?.trimEnd('/'),
        comingSoonNote = g.optNonBlank("comingSoonNote"),
      )
    }
  }.getOrElse { emptyList() }
}

private fun JSONObject.optNonBlank(name: String): String? = optString(name, "").ifBlank { null }

fun parseHexColor(hex: String): Color = runCatching {
  val c = hex.removePrefix("#")
  if (c.length >= 6) Color(c.substring(0, 2).toInt(16), c.substring(2, 4).toInt(16), c.substring(4, 6).toInt(16))
  else DefaultAccent
}.getOrElse { DefaultAccent }
