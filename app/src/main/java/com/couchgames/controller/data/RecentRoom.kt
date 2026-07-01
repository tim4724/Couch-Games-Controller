package com.couchgames.controller.data

import android.content.Context

/**
 * The last room this phone joined — enough to offer a one-tap rejoin from the
 * home screen. [joinUrl] is the resolved controller URL WITHOUT profile params
 * (it gets re-wrapped with the current name at rejoin time).
 */
data class RecentRoom(
  val joinUrl: String,
  val gameId: String,
  val roomCode: String,
)

object RecentRoomStore {
  private const val PREFS = "cg_recent"
  private const val KEY_URL = "joinUrl"
  private const val KEY_GAME = "gameId"
  private const val KEY_CODE = "roomCode"
  private const val KEY_AT = "savedAt"

  // Rooms don't outlive a couch session; past this we don't even probe the relay.
  private const val MAX_AGE_MS = 12L * 60 * 60 * 1000

  fun save(context: Context, target: JoinOutcome.Success) {
    prefs(context).edit()
      .putString(KEY_URL, target.joinUrl)
      .putString(KEY_GAME, target.game.id)
      .putString(KEY_CODE, target.roomCode)
      .putLong(KEY_AT, System.currentTimeMillis())
      .apply()
  }

  fun load(context: Context): RecentRoom? {
    val p = prefs(context)
    val url = p.getString(KEY_URL, null) ?: return null
    val game = p.getString(KEY_GAME, null) ?: return null
    val code = p.getString(KEY_CODE, null) ?: return null
    if (System.currentTimeMillis() - p.getLong(KEY_AT, 0L) > MAX_AGE_MS) return null
    return RecentRoom(url, game, code)
  }

  fun clear(context: Context) {
    prefs(context).edit().clear().apply()
  }

  private fun prefs(context: Context) =
    context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
