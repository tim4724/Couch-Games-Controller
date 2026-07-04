package com.couchgames.controller.ui.about

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.couchgames.controller.ui.components.BackScaffold

/**
 * The About hub. Lists the legal documents (privacy notice + imprint, kept
 * plainly labeled so the Impressum stays findable) and the open-source licenses.
 * Each row is two taps from home (info icon → here → document), satisfying the
 * "reachable from within the app" requirement for the Impressum.
 */
@Composable
fun AboutScreen(
  onOpenPrivacy: () -> Unit,
  onOpenImprint: () -> Unit,
  onOpenLicenses: () -> Unit,
  onBack: () -> Unit,
) {
  BackScaffold(title = "About", onBack = onBack) { innerPadding ->
    Column(Modifier.fillMaxSize().padding(innerPadding)) {
      AboutRow("Privacy Policy", onOpenPrivacy)
      HorizontalDivider()
      AboutRow("Impressum", onOpenImprint)
      HorizontalDivider()
      AboutRow("Open source licenses", onOpenLicenses)
    }
  }
}

@Composable
private fun AboutRow(label: String, onClick: () -> Unit) {
  Row(
    modifier = Modifier
      .fillMaxWidth()
      .clickable(onClick = onClick)
      .padding(horizontal = 20.dp, vertical = 18.dp),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Text(label, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null)
  }
}
