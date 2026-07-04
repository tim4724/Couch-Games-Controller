package com.couchgames.controller

import androidx.navigation3.runtime.NavKey
import kotlinx.serialization.Serializable

@Serializable data object Main : NavKey

@Serializable data object About : NavKey

@Serializable
data class GameHost(
  val joinUrl: String,
  val title: String,
  // Domains (subdomains included) the in-game WebView may navigate to; everything
  // else is bounced to the browser. The launcher's own domain is always added by
  // the host screen. This is the trust boundary for relay-supplied URLs.
  val allowedHosts: List<String>,
) : NavKey
