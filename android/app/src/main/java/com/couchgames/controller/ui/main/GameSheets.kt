package com.couchgames.controller.ui.main

import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.widget.VideoView
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.couchgames.controller.data.Game
import com.couchgames.controller.ui.components.AppSheet
import com.couchgames.controller.ui.components.StatusLabel

/**
 * Pure game info — name, gameplay loop, tagline, players. Joining lives on the
 * home's Join card; no static cover art either (the sheet opens right over the
 * card that already shows it), but a gameplay video adds motion the card doesn't have.
 */
@Composable
fun GameInfoSheet(game: Game, onDismiss: () -> Unit) {
  AppSheet(onDismiss = onDismiss) {
    Column(
      Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, top = 24.dp, bottom = 28.dp),
      verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
      Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
      ) {
        Text(game.name, style = MaterialTheme.typography.headlineSmall)
        StatusLabel(game)
      }
      game.video?.let { GameplayLoop(it) }
      Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(
          game.tagline,
          style = MaterialTheme.typography.bodyLarge,
          color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        game.players?.let {
          Text(it, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.primary)
        }
      }
      if (!game.isLive) {
        Text(
          game.comingSoonNote ?: "Coming soon to Couch Games.",
          style = MaterialTheme.typography.bodyLarge,
          color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
      }
    }
  }
}

// A muted, looping gameplay clip bundled in res/raw. VideoView over ExoPlayer:
// a local 30s loop doesn't justify the Media3 dependency.
@Composable
private fun GameplayLoop(rawName: String) {
  AndroidView(
    modifier = Modifier
      .fillMaxWidth()
      .aspectRatio(16f / 9f)
      .clip(MaterialTheme.shapes.large),
    factory = { ctx ->
      VideoView(ctx).apply {
        // The clip is muted, so never take audio focus — stock VideoView otherwise
        // pauses whatever the user is listening to. (No-op below API 26.)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
          setAudioFocusRequest(AudioManager.AUDIOFOCUS_NONE)
        }
        setVideoURI(Uri.parse("android.resource://${ctx.packageName}/raw/$rawName"))
        setOnPreparedListener { mp ->
          mp.isLooping = true
          mp.setVolume(0f, 0f)
          mp.start()
        }
      }
    },
    onRelease = { it.stopPlayback() },
  )
}
