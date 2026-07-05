package com.couchgames.controller.ui.main

import android.widget.Toast
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.windowInsetsTopHeight
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import com.couchgames.controller.data.Favicon
import com.couchgames.controller.data.Game
import com.couchgames.controller.data.GamesManifest
import com.couchgames.controller.data.JoinOutcome
import com.couchgames.controller.data.JoinResolver
import com.couchgames.controller.data.LAUNCHER_HOST
import com.couchgames.controller.data.Profile
import com.couchgames.controller.data.ProfileStore
import com.couchgames.controller.data.RecentRoom
import com.couchgames.controller.data.RecentRoomStore
import com.couchgames.controller.data.RoomDirectory
import com.couchgames.controller.data.RoomLookup
import com.couchgames.controller.data.resolveTypedCode
import com.couchgames.controller.data.withProfile
import com.couchgames.controller.R
import com.couchgames.controller.ui.components.GameArt
import com.couchgames.controller.ui.components.JoinButtons
import com.couchgames.controller.ui.components.MirrorHostSystemBars
import com.couchgames.controller.ui.components.PlayerChip
import com.couchgames.controller.ui.components.stableScreenInsets
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@Composable
fun MainScreen(
  modifier: Modifier = Modifier,
  deepLink: String? = null,
  onDeepLinkConsumed: () -> Unit = {},
  onJoin: (joinUrl: String, title: String, allowedHosts: List<String>) -> Unit = { _, _, _ -> },
  onOpenAbout: () -> Unit = {},
) {
  val context = LocalContext.current
  // Config-aware resources for string lookups in callbacks (context.getString on
  // LocalContext.current is flagged by lint as not tracking config changes).
  val resources = LocalResources.current
  val scope = rememberCoroutineScope()
  val haptics = LocalHapticFeedback.current
  val lifecycleOwner = LocalLifecycleOwner.current
  val games = remember { GamesManifest.load(context) }
  var profile by remember { mutableStateOf(ProfileStore.load(context)) }
  var showProfile by remember { mutableStateOf(false) }
  var afterName by remember { mutableStateOf<AfterName?>(null) }
  var showScanner by remember { mutableStateOf(false) }
  var showCodeEntry by remember { mutableStateOf(false) }
  var codeLoading by remember { mutableStateOf(false) }
  var codeError by remember { mutableStateOf<String?>(null) }
  var rejoin by remember { mutableStateOf<RecentRoom?>(null) }
  var infoGame by remember { mutableStateOf<Game?>(null) }

  // Every successful join funnels through here: remember the room for one-tap
  // rejoin and open the game host. Closes the scanner too, so leaving the game
  // lands back on home, not on a live camera.
  fun launchJoin(target: JoinOutcome.Success, p: Profile) {
    haptics.performHapticFeedback(HapticFeedbackType.Confirm)
    showScanner = false
    RecentRoomStore.remember(target.game, target.joinUrl, target.roomCode)
    onJoin(withProfile(target.joinUrl, p), target.game.name, target.game.hosts)
  }

  // Every failure surface — a bad link, a dead room — pairs the toast with a
  // rejection buzz, mirroring iOS's error haptic.
  fun fail(messageRes: Int, length: Int = Toast.LENGTH_SHORT) {
    haptics.performHapticFeedback(HapticFeedbackType.Reject)
    Toast.makeText(context, resources.getString(messageRes), length).show()
  }

  fun perform(action: AfterName, p: Profile) {
    when (action) {
      AfterName.Scan -> showScanner = true
      AfterName.EnterCode -> { codeError = null; showCodeEntry = true }
      is AfterName.Join -> launchJoin(action.target, p)
    }
  }

  // Gate any join behind a non-blank name: prompt first if missing, else act now.
  fun requireName(action: AfterName) {
    if (!profile.isSet) {
      afterName = action
      showProfile = true
    } else {
      perform(action, profile)
    }
  }

  fun resolveAndJoin(raw: String) {
    when (val r = JoinResolver.resolve(raw, games)) {
      is JoinOutcome.Success -> requireName(AfterName.Join(r))
      is JoinOutcome.Failure -> fail(r.messageRes)
    }
  }

  // An incoming App Link goes through the same name gate as a scan.
  LaunchedEffect(deepLink) {
    if (deepLink != null) {
      resolveAndJoin(deepLink)
      onDeepLinkConsumed()
    }
  }

  // Offer one-tap rejoin while the last-joined room is still alive: keep probing
  // the game's relay so the card clears itself when the room dies. Lifecycle-gated —
  // no polling while backgrounded.
  LaunchedEffect(Unit) {
    lifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
      val recent = RecentRoomStore.current() ?: return@repeatOnLifecycle
      // No room code (the scanned URL didn't surface one) → we can't liveness-poll, so
      // surface the card unverified. Tapping a dead room is handled by gameEnded.
      if (recent.roomCode.isBlank()) {
        rejoin = recent
        return@repeatOnLifecycle
      }
      while (true) {
        when (RoomDirectory.lookup(recent.roomCode, recent.game.roomRelayBase)) {
          is RoomLookup.Found -> rejoin = recent
          RoomLookup.NotFound -> {
            RecentRoomStore.clear()
            rejoin = null
            return@repeatOnLifecycle
          }
          RoomLookup.Error -> {} // transient — keep whatever we showed last
        }
        delay(10_000)
      }
    }
  }

  // Games scroll the full screen; the join card floats over the list at the bottom.
  // The trailing Spacer, sized off the card's measured height, keeps the last
  // poster reachable. The scanner overlay sits in the same root Box but OUTSIDE
  // the inset padding — the camera runs edge to edge and pads its own controls.
  var joinCardHeightPx by remember { mutableStateOf(0) }
  Box(modifier.fillMaxSize()) {
    // Only the horizontal (cutout) inset pads the container. The status bar and nav
    // bar are applied INSIDE the scroll (top spacer + card bottom inset) so the
    // catalog scrolls edge to edge UNDER the transparent bars instead of being
    // clipped in a box below them.
    Box(
      Modifier
        .fillMaxSize()
        .windowInsetsPadding(stableScreenInsets.only(WindowInsetsSides.Horizontal)),
    ) {
      Column(
        Modifier
          .fillMaxSize()
          .verticalScroll(rememberScrollState()),
      ) {
        // Clears the status bar so the header starts below it, but scrolls away with
        // the content — posters slide under the transparent bar, not into a hard cut.
        Spacer(Modifier.windowInsetsTopHeight(stableScreenInsets))
        // Sits OUTSIDE the 16dp content margin (owns its own padding, like the
        // in-game LeaveBar) so the title and name chip align across screens.
        HomeTopBar(profile = profile, onEditProfile = { showProfile = true }, onOpenAbout = onOpenAbout)
        Column(
          Modifier
            .padding(horizontal = 16.dp)
            .padding(top = 8.dp),
          verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
          // A relay-confirmed room springs the rejoin card in; when the room dies it
          // springs back out. Retain the last target so the exit animation still has
          // content to render after `rejoin` clears (mirrors iOS's scale+fade).
          var lastRejoin by remember { mutableStateOf<RecentRoom?>(null) }
          LaunchedEffect(rejoin) { rejoin?.let { lastRejoin = it } }
          AnimatedVisibility(
            visible = rejoin != null,
            enter = fadeIn() + scaleIn(initialScale = 0.96f),
            exit = fadeOut() + scaleOut(targetScale = 0.96f),
          ) {
            lastRejoin?.let { room ->
              RejoinCard(room) { resolveAndJoin(room.joinUrl) }
            }
          }
          GamesSection(games, onOpen = { infoGame = it })
          Spacer(Modifier.height(with(LocalDensity.current) { joinCardHeightPx.toDp() } + 12.dp))
        }
      }
      JoinCard(
        host = games.firstOrNull { it.isLive }?.displayHost ?: LAUNCHER_HOST,
        onScan = { requireName(AfterName.Scan) },
        onEnterCode = { requireName(AfterName.EnterCode) },
        modifier = Modifier
          .align(Alignment.BottomCenter)
          // Measured OUTSIDE the margins + nav-bar inset so the spacer clears the
          // whole floating card.
          .onGloballyPositioned { joinCardHeightPx = it.size.height }
          // The container no longer reserves the nav bar; lift the card above it here.
          .windowInsetsPadding(stableScreenInsets.only(WindowInsetsSides.Bottom))
          .padding(horizontal = 12.dp)
          .padding(bottom = 12.dp),
      )
    }
    // Status-bar protection: the window background at 50% alpha, one status-bar tall.
    // At rest it sits over the same background — a no-op, invisible. When a poster
    // scrolls under the bar it tints that strip back toward the background, keeping
    // the theme-colored status icons legible. No icon flipping, no poster-color
    // assumption. Sits above the catalog but below the full-screen scanner overlay.
    Box(
      Modifier
        .align(Alignment.TopCenter)
        .fillMaxWidth()
        .windowInsetsTopHeight(stableScreenInsets)
        .background(MaterialTheme.colorScheme.background.copy(alpha = 0.5f)),
    )
    if (showScanner) {
      ScanScreen(
        games = games,
        onJoin = { launchJoin(it, profile) },
        onEnterCode = { codeError = null; showCodeEntry = true },
        onClose = { showScanner = false },
      )
    }
  }

  if (showProfile) {
    val gating = afterName != null
    ProfileSheet(
      initial = profile,
      title = stringResource(if (gating) R.string.enter_your_name else R.string.name),
      cta = stringResource(if (gating) R.string.save_and_continue else R.string.save),
      onDismiss = {
        showProfile = false
        afterName = null
      },
      onSave = { saved ->
        ProfileStore.save(context, saved)
        profile = saved
        showProfile = false
        val a = afterName
        afterName = null
        if (a != null) perform(a, saved)
      },
    )
  }

  if (showCodeEntry) {
    CodeEntryDialog(
      loading = codeLoading,
      error = codeError,
      onDismiss = {
        if (!codeLoading) {
          showCodeEntry = false
          codeError = null
        }
      },
      onSubmit = { code ->
        codeError = null
        codeLoading = true
        scope.launch {
          val outcome = resolveTypedCode(code.trim(), games)
          codeLoading = false
          when (outcome) {
            is JoinOutcome.Success -> {
              showCodeEntry = false
              launchJoin(outcome, profile)
            }
            is JoinOutcome.Failure -> {
              haptics.performHapticFeedback(HapticFeedbackType.Reject)
              codeError = resources.getString(outcome.messageRes)
            }
          }
        }
      },
    )
  }

  infoGame?.let { game ->
    GameInfoSheet(
      game = game,
      onDismiss = { infoGame = null },
      onScan = { infoGame = null; requireName(AfterName.Scan) },
      onEnterCode = { infoGame = null; requireName(AfterName.EnterCode) },
    )
  }
}

// A join action deferred until the player has a name (see requireName).
private sealed interface AfterName {
  data object Scan : AfterName
  data object EnterCode : AfterName
  data class Join(val target: JoinOutcome.Success) : AfterName
}

// Home chrome, structurally identical to the in-game LeaveBar so the title and
// name chip land in the same place across screens (GameHostScreen.kt).
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun HomeTopBar(profile: Profile, onEditProfile: () -> Unit, onOpenAbout: () -> Unit) {
  TopAppBar(
    title = {
      Column {
        Text(
          stringResource(R.string.app_name),
          style = MaterialTheme.typography.titleLarge,
          fontWeight = FontWeight.SemiBold,
        )
        Text(
          stringResource(R.string.home_subtitle),
          style = MaterialTheme.typography.labelMedium,
          color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
      }
    },
    actions = {
      PlayerChip(name = profile.name, onClick = onEditProfile)
      IconButton(onClick = onOpenAbout) {
        Icon(Icons.Outlined.Info, contentDescription = stringResource(R.string.about))
      }
      Spacer(Modifier.width(8.dp))
    },
    // The host Box already pads status bar + cutout; don't let the bar re-add them.
    windowInsets = WindowInsets(0),
    colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Transparent),
  )
}

// Tactile press feedback shared by the tappable cards: a subtle spring scale-down
// while held, matching iOS's PressableCardButtonStyle.
@Composable
private fun rememberPressScale(interaction: MutableInteractionSource): Float {
  val pressed by interaction.collectIsPressedAsState()
  val scale by animateFloatAsState(
    targetValue = if (pressed) 0.97f else 1f,
    animationSpec = spring(stiffness = Spring.StiffnessMediumLow),
    label = "cardPress",
  )
  return scale
}

@Composable
private fun RejoinCard(room: RecentRoom, onClick: () -> Unit) {
  val interaction = remember { MutableInteractionSource() }
  val scale = rememberPressScale(interaction)
  // The controller's own page title (captured this session), falling back to the
  // manifest's curated name until it's captured.
  val name = room.title ?: room.game.name
  Card(
    onClick = onClick,
    modifier = Modifier
      .fillMaxWidth()
      .graphicsLayer { scaleX = scale; scaleY = scale },
    interactionSource = interaction,
    colors = CardDefaults.cardColors(
      containerColor = MaterialTheme.colorScheme.secondaryContainer,
      contentColor = MaterialTheme.colorScheme.onSecondaryContainer,
    ),
  ) {
    Row(
      Modifier.padding(16.dp),
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
      RejoinIcon(room.favicon)
      Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(
          name,
          style = MaterialTheme.typography.titleMedium,
          maxLines = 1,
          overflow = TextOverflow.Ellipsis,
        )
        if (room.roomCode.isNotBlank()) {
          Text(
            stringResource(R.string.room_code_label, room.roomCode),
            style = MaterialTheme.typography.bodyMedium,
          )
        }
      }
      Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null)
    }
  }
}

// The rejoin card's leading glyph: the game's captured controller favicon on a tile
// whose shade is chosen from the icon's OWN content — a dark plate under a
// light/transparent icon, a white plate under a dark one — so it never washes out
// against the light card or a same-toned plate. Falls back to a play arrow when
// nothing's been captured this session.
@Composable
private fun RejoinIcon(favicon: Favicon?) {
  val fav = favicon
  if (fav != null) {
    val plate = if (fav.contentIsLight) Color(0xFF202024) else Color.White
    Box(
      Modifier
        .size(48.dp)
        .clip(RoundedCornerShape(12.dp))
        .background(plate)
        .border(1.dp, MaterialTheme.colorScheme.outlineVariant, RoundedCornerShape(12.dp)),
      contentAlignment = Alignment.Center,
    ) {
      // ~10dp of breathing room inside the tile so the icon never touches the edge.
      Image(
        fav.image,
        contentDescription = null,
        modifier = Modifier.size(28.dp).clip(RoundedCornerShape(8.dp)),
        contentScale = ContentScale.Fit,
      )
    }
  } else {
    Icon(Icons.Filled.PlayArrow, contentDescription = null, Modifier.size(34.dp))
  }
}

// Every game — live or coming soon — gets the same full-width poster card.
@Composable
private fun GamesSection(games: List<Game>, onOpen: (Game) -> Unit) {
  Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
    games.forEach { game -> GameCard(game, onOpen) }
  }
}

// Poster tile: name/tagline/status sit ON the art over a bottom scrim, so the
// scrim colors are fixed (white text on black gradient) in both themes.
@Composable
private fun GameCard(game: Game, onOpen: (Game) -> Unit) {
  val interaction = remember { MutableInteractionSource() }
  val scale = rememberPressScale(interaction)
  ElevatedCard(
    onClick = { onOpen(game) },
    modifier = Modifier.fillMaxWidth().graphicsLayer { scaleX = scale; scaleY = scale },
    interactionSource = interaction,
  ) {
    Box {
      // 16:9 matches the screenshots — a shorter crop would slice the per-player
      // HUD chips in the corners of each quadrant.
      GameArt(game, Modifier.fillMaxWidth().aspectRatio(16f / 9f))
      Box(
        Modifier.matchParentSize().background(
          Brush.verticalGradient(
            0.55f to Color.Transparent,
            1f to Color.Black.copy(alpha = 0.86f),
          ),
        ),
      )
      Row(
        Modifier.align(Alignment.BottomStart).fillMaxWidth().padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
      ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
          Text(game.name, style = MaterialTheme.typography.titleMedium, color = Color.White)
        }
        PosterStatusChip(game)
      }
    }
  }
}

// Solid accent = live, accent-tinted dark = coming soon. The chip can land on
// bright art (the scrim thins toward its top), so the soon-variant needs its own
// dark base rather than a bare translucent tint.
@Composable
private fun PosterStatusChip(game: Game) {
  val bg =
    if (game.isLive) game.accentColor
    else game.accentColor.copy(alpha = 0.32f).compositeOver(Color.Black.copy(alpha = 0.55f))
  val fg = if (game.isLive) Color.Black.copy(alpha = 0.85f) else Color.White
  Text(
    stringResource(if (game.isLive) R.string.status_live else R.string.status_coming_soon),
    style = MaterialTheme.typography.labelMedium,
    color = fg,
    modifier = Modifier
      .clip(CircleShape)
      .background(bg)
      .padding(horizontal = 10.dp, vertical = 4.dp),
  )
}

// The floating join card pinned over the scrolling catalog: browse first, act at
// the thumb. Order and copy per design.
@Composable
private fun JoinCard(
  host: String,
  onScan: () -> Unit,
  onEnterCode: () -> Unit,
  modifier: Modifier = Modifier,
) {
  Surface(
    modifier = modifier.fillMaxWidth(),
    shape = MaterialTheme.shapes.extraLarge,
    color = MaterialTheme.colorScheme.surfaceContainerHigh,
    // A hairline border does the "lift" in light mode; a heavy drop-shadow just
    // reads as a gray blob on the near-white base.
    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
    shadowElevation = 2.dp,
  ) {
    Column(
      Modifier.fillMaxWidth().padding(16.dp),
      verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
      Text(stringResource(R.string.join_title), style = MaterialTheme.typography.titleLarge)
      // The localized template positions the host; the host itself gets the
      // semibold-accent span wherever the language puts it.
      val template = stringResource(R.string.join_open_host)
      Text(
        buildAnnotatedString {
          val at = template.indexOf("%1\$s")
          append(template.substring(0, at))
          withStyle(
            SpanStyle(fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary),
          ) { append(host) }
          append(template.substring(at + 4))
        },
        style = MaterialTheme.typography.bodyLarge,
      )
      JoinButtons(onScan = onScan, onEnterCode = onEnterCode)
    }
  }
}

// Typed codes resolve via the relay directory (a bare code carries no domain).
// Never auto-uppercases — room codes are case-sensitive base58.
@Composable
private fun CodeEntryDialog(
  loading: Boolean,
  error: String?,
  onSubmit: (String) -> Unit,
  onDismiss: () -> Unit,
) {
  var code by remember { mutableStateOf("") }
  AlertDialog(
    onDismissRequest = onDismiss,
    title = { Text(stringResource(R.string.enter_room_code)) },
    text = {
      MirrorHostSystemBars()
      OutlinedTextField(
        value = code,
        onValueChange = { if (it.length <= 16) code = it },
        placeholder = { Text(stringResource(R.string.code_placeholder)) },
        singleLine = true,
        isError = error != null,
        supportingText = { if (error != null) Text(error) },
        modifier = Modifier.fillMaxWidth(),
      )
    },
    confirmButton = {
      TextButton(onClick = { onSubmit(code) }, enabled = code.isNotBlank() && !loading) {
        Text(stringResource(if (loading) R.string.joining else R.string.join))
      }
    },
    dismissButton = {
      TextButton(onClick = onDismiss, enabled = !loading) { Text(stringResource(R.string.cancel)) }
    },
  )
}
