package com.couchgames.controller

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.navigation3.runtime.entryProvider
import androidx.navigation3.runtime.rememberNavBackStack
import androidx.navigation3.ui.NavDisplay
import com.couchgames.controller.ui.about.AboutScreen
import com.couchgames.controller.ui.about.LicensesScreen
import com.couchgames.controller.ui.components.stableScreenInsets
import com.couchgames.controller.ui.game.GameHostScreen
import com.couchgames.controller.ui.legal.LegalLinks
import com.couchgames.controller.ui.legal.WebDocScreen
import com.couchgames.controller.ui.main.MainScreen
import kotlinx.coroutines.launch

@Composable
fun MainNavigation(deepLink: String? = null, onDeepLinkConsumed: () -> Unit = {}) {
  val backStack = rememberNavBackStack(Main)
  val scope = rememberCoroutineScope()
  val snackbarHostState = remember { SnackbarHostState() }

  // An external App Link routes through MainScreen (which owns the name gate + join).
  // Pop back to Main first so it's the active entry and can handle it.
  LaunchedEffect(deepLink) {
    if (deepLink != null) while (backStack.size > 1) backStack.removeLastOrNull()
  }

  Box(Modifier.fillMaxSize()) {
    NavDisplay(
      backStack = backStack,
      onBack = { backStack.removeLastOrNull() },
      entryProvider = entryProvider {
        entry<Main> {
          MainScreen(
            deepLink = deepLink,
            onDeepLinkConsumed = onDeepLinkConsumed,
            onJoin = { joinUrl, title, allowedHosts ->
              backStack.add(GameHost(joinUrl, title, allowedHosts))
            },
            onOpenAbout = { backStack.add(About) },
          )
        }
        entry<About> {
          AboutScreen(
            onOpenPrivacy = { backStack.add(WebDoc(LegalLinks.PRIVACY_URL, "Privacy Policy")) },
            onOpenImprint = { backStack.add(WebDoc(LegalLinks.IMPRINT_URL, "Impressum")) },
            onOpenLicenses = { backStack.add(Licenses) },
            onBack = { backStack.removeLastOrNull() },
          )
        }
        entry<Licenses> {
          LicensesScreen(onBack = { backStack.removeLastOrNull() })
        }
        entry<WebDoc> { key ->
          WebDocScreen(
            url = key.url,
            title = key.title,
            onBack = { backStack.removeLastOrNull() },
          )
        }
        entry<GameHost> { key ->
          GameHostScreen(
            joinUrl = key.joinUrl,
            title = key.title,
            allowedHosts = key.allowedHosts,
            onLeave = { backStack.removeLastOrNull() },
            // Game-reported session end: back home like LEAVE, plus a snackbar —
            // the player didn't choose to leave, so silence would read as a crash.
            onGameEnd = { reason ->
              backStack.removeLastOrNull()
              scope.launch { snackbarHostState.showSnackbar(gameEndMessage(reason)) }
            },
          )
        }
      },
    )
    // Hosted above NavDisplay so the message survives the GameHost→Main pop.
    SnackbarHost(
      hostState = snackbarHostState,
      modifier = Modifier
        .align(Alignment.BottomCenter)
        .windowInsetsPadding(stableScreenInsets),
    )
  }
}

// Player-facing copy for the contract's session-end reasons. The string comes from
// web content (untrusted), so anything unrecognized falls back to the generic line.
private fun gameEndMessage(reason: String?): String = when (reason) {
  "room_not_found" -> "Room not found"
  "game_full" -> "Room is full"
  "replaced" -> "You joined from another device"
  else -> "The party ended"
}
