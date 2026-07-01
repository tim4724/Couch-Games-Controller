package com.couchgames.controller.ui.main

import android.content.Context
import android.widget.Toast
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
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
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
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
import com.couchgames.controller.ui.components.MirrorHostSystemBars
import com.couchgames.controller.ui.components.PlayerChip
import com.couchgames.controller.ui.components.stableScreenInsets
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun MainScreen(
  modifier: Modifier = Modifier,
  deepLink: String? = null,
  onDeepLinkConsumed: () -> Unit = {},
  onJoin: (joinUrl: String, title: String, allowedHosts: List<String>) -> Unit = { _, _, _ -> },
  onOpenAbout: () -> Unit = {},
) {
  val context = LocalContext.current
  val scope = rememberCoroutineScope()
  val lifecycleOwner = LocalLifecycleOwner.current
  val games = remember { GamesManifest.load(context) }
  var profile by remember { mutableStateOf(ProfileStore.load(context)) }
  var showProfile by remember { mutableStateOf(false) }
  var afterName by remember { mutableStateOf<AfterName?>(null) }
  var showCodeEntry by remember { mutableStateOf(false) }
  var codeLoading by remember { mutableStateOf(false) }
  var codeError by remember { mutableStateOf<String?>(null) }
  var rejoin by remember { mutableStateOf<RejoinTarget?>(null) }
  var infoGame by remember { mutableStateOf<Game?>(null) }

  // Every successful join funnels through here: remember the room for one-tap
  // rejoin and open the game host.
  fun launchJoin(target: JoinOutcome.Success, p: Profile) {
    RecentRoomStore.save(context, target)
    onJoin(withProfile(target.joinUrl, p), target.game.name, target.game.hosts)
  }

  fun perform(action: AfterName, p: Profile) {
    when (action) {
      AfterName.Scan -> startScan(context, games) { launchJoin(it, p) }
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
      is JoinOutcome.Failure -> Toast.makeText(context, r.message, Toast.LENGTH_SHORT).show()
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
      val recent = withContext(Dispatchers.IO) { RecentRoomStore.load(context) }
        ?: return@repeatOnLifecycle
      val game = games.firstOrNull { it.id == recent.gameId } ?: return@repeatOnLifecycle
      while (true) {
        when (RoomDirectory.lookup(recent.roomCode, game.roomRelayBase)) {
          is RoomLookup.Found -> rejoin = RejoinTarget(recent, game)
          RoomLookup.NotFound -> {
            withContext(Dispatchers.IO) { RecentRoomStore.clear(context) }
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
  // poster reachable.
  var joinCardHeightPx by remember { mutableStateOf(0) }
  Box(
    modifier
      .fillMaxSize()
      .windowInsetsPadding(stableScreenInsets),
  ) {
    Column(
      Modifier
        .fillMaxSize()
        .verticalScroll(rememberScrollState()),
    ) {
      // Sits OUTSIDE the 16dp content margin (owns its own padding, like the
      // in-game LeaveBar) so the title and name chip align across screens.
      HomeTopBar(profile = profile, onEditProfile = { showProfile = true })
      Column(
        Modifier
          .padding(horizontal = 16.dp)
          .padding(top = 8.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp),
      ) {
        rejoin?.let { target ->
          RejoinCard(target) { resolveAndJoin(target.room.joinUrl) }
        }
        GamesSection(games, onOpen = { infoGame = it })
        AboutFooter(onOpenAbout)
        Spacer(Modifier.height(with(LocalDensity.current) { joinCardHeightPx.toDp() } + 12.dp))
      }
    }
    JoinCard(
      host = games.firstOrNull { it.isLive }?.displayHost ?: LAUNCHER_HOST,
      onScan = { requireName(AfterName.Scan) },
      onEnterCode = { requireName(AfterName.EnterCode) },
      modifier = Modifier
        .align(Alignment.BottomCenter)
        // Measured OUTSIDE the margins so the spacer clears card + margins.
        .onGloballyPositioned { joinCardHeightPx = it.size.height }
        .padding(horizontal = 12.dp)
        .padding(bottom = 12.dp),
    )
  }

  if (showProfile) {
    val gating = afterName != null
    ProfileSheet(
      initial = profile,
      title = if (gating) "Enter your name" else "Your player",
      cta = if (gating) "Save & continue" else "Save",
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
            is JoinOutcome.Failure -> codeError = outcome.message
          }
        }
      },
    )
  }

  infoGame?.let { game ->
    GameInfoSheet(game = game, onDismiss = { infoGame = null })
  }
}

// A join action deferred until the player has a name (see requireName).
private sealed interface AfterName {
  data object Scan : AfterName
  data object EnterCode : AfterName
  data class Join(val target: JoinOutcome.Success) : AfterName
}

// A relay-confirmed alive room from a previous session.
private data class RejoinTarget(val room: RecentRoom, val game: Game)

// Play Services code scanner — on-device, no CAMERA permission needed.
private fun startScan(
  context: Context,
  games: List<Game>,
  onResolved: (JoinOutcome.Success) -> Unit,
) {
  val options = GmsBarcodeScannerOptions.Builder()
    .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
    .build()
  GmsBarcodeScanning.getClient(context, options).startScan()
    .addOnSuccessListener { barcode ->
      when (val r = JoinResolver.resolve(barcode.rawValue, games)) {
        is JoinOutcome.Success -> onResolved(r)
        is JoinOutcome.Failure ->
          Toast.makeText(context, r.message, Toast.LENGTH_SHORT).show()
      }
    }
    .addOnFailureListener { e ->
      Toast.makeText(context, "Scanner unavailable: ${e.message}", Toast.LENGTH_LONG).show()
    }
}

// Home chrome, structurally identical to the in-game LeaveBar so the title and
// name chip land in the same place across screens (GameHostScreen.kt).
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun HomeTopBar(profile: Profile, onEditProfile: () -> Unit) {
  TopAppBar(
    title = {
      Column {
        Text(
          "Couch Games",
          style = MaterialTheme.typography.titleLarge,
          fontWeight = FontWeight.SemiBold,
        )
        Text(
          "Controller",
          style = MaterialTheme.typography.labelMedium,
          color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
      }
    },
    actions = {
      PlayerChip(name = profile.name, onClick = onEditProfile)
      Spacer(Modifier.width(12.dp))
    },
    // The host Box already pads status bar + cutout; don't let the bar re-add them.
    windowInsets = WindowInsets(0),
    colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Transparent),
  )
}

@Composable
private fun RejoinCard(target: RejoinTarget, onClick: () -> Unit) {
  Card(
    onClick = onClick,
    modifier = Modifier.fillMaxWidth(),
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
      Icon(Icons.Filled.PlayArrow, contentDescription = null, Modifier.size(28.dp))
      Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text("Rejoin ${target.game.name}", style = MaterialTheme.typography.titleMedium)
        Text(
          "Room ${target.room.roomCode}",
          style = MaterialTheme.typography.bodyMedium,
        )
      }
      Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null)
    }
  }
}

@Composable
private fun AboutFooter(onOpenAbout: () -> Unit) {
  TextButton(
    onClick = onOpenAbout,
    modifier = Modifier.fillMaxWidth(),
  ) {
    Text(
      "Open source licenses",
      style = MaterialTheme.typography.labelLarge,
      color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
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
  val pressed by interaction.collectIsPressedAsState()
  val scale by animateFloatAsState(
    targetValue = if (pressed) 0.97f else 1f,
    animationSpec = spring(stiffness = Spring.StiffnessMediumLow),
    label = "cardPress",
  )
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
          Text(
            game.tagline,
            style = MaterialTheme.typography.bodySmall,
            color = Color.White.copy(alpha = 0.82f),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
          )
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
    if (game.isLive) "Live" else "Coming soon",
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
      Text("Join", style = MaterialTheme.typography.titleLarge)
      Text(
        buildAnnotatedString {
          append("Open ")
          withStyle(
            SpanStyle(fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary),
          ) { append(host) }
          append(" on your TV or laptop.")
        },
        style = MaterialTheme.typography.bodyLarge,
      )
      Button(onClick = onScan, modifier = Modifier.fillMaxWidth().height(56.dp)) {
        Icon(painterResource(R.drawable.ic_qr_scan), contentDescription = null, Modifier.size(22.dp))
        Spacer(Modifier.width(10.dp))
        Text("Scan code", style = MaterialTheme.typography.titleMedium)
      }
      FilledTonalButton(onClick = onEnterCode, modifier = Modifier.fillMaxWidth().height(56.dp)) {
        Text("Enter code manually", style = MaterialTheme.typography.titleMedium)
      }
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
    title = { Text("Enter room code") },
    text = {
      MirrorHostSystemBars()
      OutlinedTextField(
        value = code,
        onValueChange = { if (it.length <= 16) code = it },
        placeholder = { Text("e.g. A3KX9p") },
        singleLine = true,
        isError = error != null,
        supportingText = { if (error != null) Text(error) },
        modifier = Modifier.fillMaxWidth(),
      )
    },
    confirmButton = {
      TextButton(onClick = { onSubmit(code) }, enabled = code.isNotBlank() && !loading) {
        Text(if (loading) "Joining…" else "Join")
      }
    },
    dismissButton = {
      TextButton(onClick = onDismiss, enabled = !loading) { Text("Cancel") }
    },
  )
}
