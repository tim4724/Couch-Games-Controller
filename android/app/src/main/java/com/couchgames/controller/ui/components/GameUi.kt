package com.couchgames.controller.ui.components

import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.couchgames.controller.data.Game
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

// The tappable player identity — home header and in-game bar. [accented]: name,
// icon, and outline take `primary`, which the game host has already remapped to
// the game's cg-accent-color.
@Composable
fun PlayerChip(name: String, onClick: () -> Unit, accented: Boolean = false) {
  AssistChip(
    onClick = onClick,
    modifier = Modifier.height(40.dp),
    label = {
      Text(
        name.ifBlank { "Set name" },
        style = MaterialTheme.typography.bodyLarge,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
      )
    },
    leadingIcon = {
      Icon(Icons.Filled.Person, contentDescription = null, Modifier.size(20.dp))
    },
    colors =
      if (accented) {
        AssistChipDefaults.assistChipColors(
          labelColor = MaterialTheme.colorScheme.primary,
          leadingIconContentColor = MaterialTheme.colorScheme.primary,
        )
      } else {
        AssistChipDefaults.assistChipColors()
      },
    border =
      if (accented) {
        AssistChipDefaults.assistChipBorder(enabled = true, borderColor = MaterialTheme.colorScheme.primary)
      } else {
        AssistChipDefaults.assistChipBorder(enabled = true)
      },
  )
}

// Decoded once per asset, off the main thread — opening a sheet never decodes
// mid-animation.
private val artCache = ConcurrentHashMap<String, ImageBitmap>()

/**
 * Cover art or, when a game has none yet, its accent as a soft gradient. The
 * accent is the one place a game's own branding shows outside the WebView.
 */
@Composable
fun GameArt(game: Game, modifier: Modifier = Modifier) {
  val context = LocalContext.current
  val img by produceState(initialValue = game.art?.let(artCache::get), game.art) {
    val path = game.art ?: return@produceState
    if (value == null) {
      value = withContext(Dispatchers.IO) {
        runCatching {
          context.assets.open(path).use { BitmapFactory.decodeStream(it) }?.asImageBitmap()
        }.getOrNull()?.also { artCache[path] = it }
      }
    }
  }
  Box(modifier.background(MaterialTheme.colorScheme.surfaceVariant)) {
    val bitmap = img
    if (bitmap != null) {
      Image(bitmap, contentDescription = game.name, modifier = Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
    } else {
      Box(
        Modifier.fillMaxSize().background(
          Brush.linearGradient(listOf(game.accentColor.copy(alpha = 0.50f), game.accentColor.copy(alpha = 0.14f))),
        ),
      )
    }
  }
}

/** Numbered instruction row — the home's how-to and the game sheet share it. */
@Composable
fun StepRow(n: Int, text: AnnotatedString) {
  Row(
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(12.dp),
  ) {
    Box(
      Modifier.size(28.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primaryContainer),
      contentAlignment = Alignment.Center,
    ) {
      Text(
        "$n",
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.onPrimaryContainer,
      )
    }
    Text(text, style = MaterialTheme.typography.bodyLarge)
  }
}

@Composable
fun StatusLabel(game: Game) {
  if (game.isLive) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
      Box(Modifier.size(8.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primary))
      Text("Live", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
    }
  } else {
    Text(
      "Coming soon",
      style = MaterialTheme.typography.labelLarge,
      color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
  }
}
