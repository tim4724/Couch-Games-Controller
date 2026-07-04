package com.couchgames.controller.ui.legal

// Hosted legal pages, served on the launcher's own domain. Shown in-app via
// WebDocScreen (a plain WebView) so they stay reachable from within the app —
// which the German Impressum obligation (§5 DDG) requires, and GDPR expects for
// the privacy notice. Same operator hosts both the app and these pages.
object LegalLinks {
  const val PRIVACY_URL = "https://couch-games.com/privacy"
  const val IMPRINT_URL = "https://couch-games.com/imprint"
}
