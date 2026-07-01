package com.couchgames.controller.data

import android.net.Uri
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

// One relay for every game. It doubles as the room→controller directory: a room
// stores the controller-URL template its host declared on create, and the probe
// below hands it back filled in (see the Party-Sockets `url` field).
const val RELAY_BASE = "https://ws.couch-games.com"

sealed interface RoomLookup {
  /** [url] is the host-declared controller URL for the room — UNTRUSTED; host-check it. */
  data class Found(val url: String?) : RoomLookup
  data object NotFound : RoomLookup
  data object Error : RoomLookup
}

object RoomDirectory {
  /** Probe the relay for a room code. Never throws; network failure → [RoomLookup.Error]. */
  suspend fun lookup(code: String, relayBase: String = RELAY_BASE): RoomLookup = withContext(Dispatchers.IO) {
    val trimmed = code.trim()
    if (trimmed.isEmpty()) return@withContext RoomLookup.NotFound
    val conn = runCatching {
      (URL("$relayBase/room/${Uri.encode(trimmed)}").openConnection() as HttpURLConnection).apply {
        requestMethod = "GET"
        connectTimeout = 5000
        readTimeout = 5000
      }
    }.getOrElse { return@withContext RoomLookup.Error }
    try {
      when (conn.responseCode) {
        200 -> {
          val json = JSONObject(conn.inputStream.bufferedReader().use { it.readText() })
          RoomLookup.Found(url = json.optString("url", "").ifBlank { null })
        }
        404 -> RoomLookup.NotFound
        else -> RoomLookup.Error
      }
    } catch (_: Exception) {
      RoomLookup.Error
    } finally {
      conn.disconnect()
    }
  }
}

/**
 * Resolve a hand-typed room code to a join target. A relay tells us which game owns
 * the code (via its stored controller URL); we then re-validate that URL's host
 * against the manifest allow-list — the relay's URL is host-declared and untrusted.
 *
 * The shared relay ([RELAY_BASE]) doesn't yet own every game's rooms, so we also
 * query the sole live game's own relay ([Game.relayProbeBase]) IN PARALLEL and take
 * whichever actually has the code — its host-declared `url` is what loads (e.g.
 * `main.hexstacker.com/<code>`), NOT the manifest's `controllerBaseUrl`. The game's
 * own relay is preferred when both answer. With more than one live game there is no
 * sole relay to fall back to, so only the shared relay is consulted.
 */
suspend fun resolveTypedCode(code: String, games: List<Game>): JoinOutcome = coroutineScope {
  val trimmed = code.trim()
  if (trimmed.isEmpty()) return@coroutineScope JoinOutcome.Failure("Enter a room code.")
  val sole = games.singleOrNull { it.isLive }

  // Race the game's own relay (first, so it wins ties) and the shared directory.
  val relays = buildList {
    sole?.relayProbeBase?.let(::add)
    if (RELAY_BASE !in this) add(RELAY_BASE)
  }
  val results = relays.map { base -> async { RoomDirectory.lookup(trimmed, base) } }.awaitAll()

  val founds = results.filterIsInstance<RoomLookup.Found>()
  val foundUrl = founds.firstOrNull { it.url != null }?.url
  when {
    // A relay knows the room and handed back the controller URL — load exactly that.
    foundUrl != null -> JoinResolver.resolve(foundUrl, games)
    // Room exists but the relay stored no URL: the sole live game hosts it.
    founds.isNotEmpty() && sole != null -> JoinResolver.resolve(trimmed, games)
    founds.isNotEmpty() -> JoinOutcome.Failure("This code can't be matched to a game right now.")
    // No relay had the room. If any errored we couldn't truly verify — with a sole
    // live game, resolve optimistically and let its own page decide.
    sole != null && results.any { it is RoomLookup.Error } -> JoinResolver.resolve(trimmed, games)
    results.any { it is RoomLookup.NotFound } -> JoinOutcome.Failure("Room not found or expired.")
    else -> JoinOutcome.Failure("Couldn't reach the server. Try again.")
  }
}
