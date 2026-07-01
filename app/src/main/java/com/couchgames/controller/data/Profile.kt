package com.couchgames.controller.data

import android.content.Context
import android.net.Uri

/**
 * The player's shared identity — just a name, entered once and handed to every game.
 * Color is deliberately NOT part of the native identity: each game owns its own color
 * (it resolves slot-conflicts), so the launcher stays out of it.
 */
data class Profile(val name: String = "") {
  val isSet: Boolean get() = name.isNotBlank()
}

object ProfileStore {
  private const val PREFS = "cg_profile"
  private const val KEY_NAME = "name"

  fun load(context: Context): Profile {
    val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    return Profile(p.getString(KEY_NAME, "").orEmpty())
  }

  fun save(context: Context, profile: Profile) {
    context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
      .putString(KEY_NAME, profile.name)
      .apply()
  }
}

/**
 * Launcher→game identity contract (v1): append the player's name to the join URL so
 * the game can prefill it and skip its own name screen. Live changes are pushed
 * separately via the window.CouchGames.setName() JS bridge (see GameHostScreen).
 * Preserves any existing ?claim and #instance; no-op when there's no name.
 */
fun withProfile(joinUrl: String, profile: Profile): String {
  if (!profile.isSet) return joinUrl
  return Uri.parse(joinUrl).buildUpon()
    .appendQueryParameter("cgv", "1")
    .appendQueryParameter("cgName", profile.name)
    .build().toString()
}
