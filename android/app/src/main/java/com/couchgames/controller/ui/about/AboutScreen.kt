package com.couchgames.controller.ui.about

import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import com.couchgames.controller.R
import com.mikepenz.aboutlibraries.ui.compose.android.produceLibraries
import com.mikepenz.aboutlibraries.ui.compose.m3.LibrariesContainer

// Google's proprietary SDK terms, pulled in transitively by the QR scanner
// (Play Services + ML Kit). They aren't open-source licenses, so libraries whose
// only license is one of these are hidden from this screen. See the plugin's
// generated license names in R.raw.aboutlibraries.
private val NON_OSS_LICENSES = setOf(
  "Android Software Development Kit License",
  "ML Kit Terms of Service",
)

/**
 * Open-source license list. The library definitions are generated at build time by
 * the AboutLibraries Gradle plugin into `R.raw.aboutlibraries` — there's no runtime
 * dependency scan, so [produceLibraries] just parses the bundled JSON.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AboutScreen(onBack: () -> Unit) {
  // safeDrawing so the app bar clears the status bar and the list clears the nav
  // bar — this screen isn't immersive like the home/game screens.
  Scaffold(
    contentWindowInsets = WindowInsets.safeDrawing,
    topBar = {
      TopAppBar(
        title = { Text("Open source licenses") },
        navigationIcon = {
          IconButton(onClick = onBack) {
            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
          }
        },
      )
    },
  ) { innerPadding ->
    val all by produceLibraries(R.raw.aboutlibraries)
    // Keep only libraries carrying at least one genuine open-source license — drops
    // the Google SDKs whose only license is a proprietary terms-of-service.
    val libraries = remember(all) {
      all?.let { libs ->
        libs.copy(libraries = libs.libraries.filter { lib ->
          lib.licenses.any { it.name !in NON_OSS_LICENSES }
        })
      }
    }
    LibrariesContainer(
      libraries = libraries,
      modifier = Modifier.fillMaxSize().padding(innerPadding),
    )
  }
}
