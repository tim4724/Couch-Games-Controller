package com.couchgames.controller

import android.content.Intent
import androidx.core.net.toUri
import androidx.compose.animation.ContentTransform
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
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
  val context = LocalContext.current

  // An external App Link routes through MainScreen (which owns the name gate + join).
  // Pop back to Main first so it's the active entry and can handle it.
  LaunchedEffect(deepLink) {
    if (deepLink != null) while (backStack.size > 1) backStack.removeLastOrNull()
  }

  Box(Modifier.fillMaxSize()) {
    NavDisplay(
      backStack = backStack,
      onBack = { backStack.removeLastOrNull() },
      // Nav3's default predictive-back spec scales the outgoing screen to 0.7 with no
      // fade, so an edge-swipe close looked different from a button/pop close (a plain
      // fade). Override it to the same crossfade so every back animates identically.
      predictivePopTransitionSpec = {
        ContentTransform(
          fadeIn(animationSpec = tween(700)),
          fadeOut(animationSpec = tween(700)),
        )
      },
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
            onOpenPrivacy = { backStack.add(WebDoc(LegalLinks.PRIVACY_URL)) },
            onOpenImprint = { backStack.add(WebDoc(LegalLinks.IMPRINT_URL)) },
            onOpenLicenses = { backStack.add(Licenses) },
            // The marketing site is a full website, not a legal doc, so it opens in
            // the system browser rather than the in-app WebDocScreen viewer.
            onOpenWebsite = {
              context.startActivity(Intent(Intent.ACTION_VIEW, LegalLinks.WEBSITE_URL.toUri()))
            },
            onBack = { backStack.removeLastOrNull() },
          )
        }
        entry<Licenses> {
          LicensesScreen(onBack = { backStack.removeLastOrNull() })
        }
        entry<WebDoc> { key ->
          // Both titles are resolved here (re-localizing with the device language); the
          // screen shows the one matching its URL. A cross-link opens the other doc as
          // its own entry so the back button returns here.
          WebDocScreen(
            url = key.url,
            privacyTitle = stringResource(R.string.privacy_policy),
            imprintTitle = stringResource(R.string.imprint),
            onOpenDoc = { backStack.add(WebDoc(it)) },
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
              scope.launch { snackbarHostState.showSnackbar(context.getString(gameEndMessage(reason))) }
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
private fun gameEndMessage(reason: String?): Int = when (reason) {
  "room_not_found" -> R.string.game_end_room_not_found
  "game_full" -> R.string.game_end_room_full
  "replaced" -> R.string.game_end_replaced
  else -> R.string.game_end_generic
}
