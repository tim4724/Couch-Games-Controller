package com.couchgames.controller.ui.legal

import android.net.Uri
import com.couchgames.controller.data.LAUNCHER_HOST

// Hosted legal pages, served on the launcher's own domain. Shown in-app via
// WebDocScreen (a plain WebView) so they stay reachable from within the app —
// which the German Impressum obligation (§5 DDG) requires, and GDPR expects for
// the privacy notice. Same operator hosts both the app and these pages.
object LegalLinks {
  const val PRIVACY_URL = "https://couch-games.com/privacy"
  const val IMPRINT_URL = "https://couch-games.com/imprint"

  // The launcher's public marketing site. Opened in the system browser (a full site,
  // not an in-app legal doc), but lives here since it's the same couch-games.com root.
  const val WEBSITE_URL = "https://couch-games.com"

  // The two legal pages cross-link to each other, so the in-app viewer can navigate
  // from one to the other without leaving the screen. These match the loaded URL back
  // to a document so the native app bar can show the right title as the page changes.
  fun isPrivacy(url: String): Boolean = matchesPath(url, "/privacy")

  fun isImprint(url: String): Boolean = matchesPath(url, "/imprint")

  private fun matchesPath(url: String, path: String): Boolean =
    url.substringBefore('?').substringBefore('#').trimEnd('/').endsWith(path)

  // A scanned QR payload is arbitrary content — unlike an App Link, the OS hasn't
  // vouched for its host, and [isPrivacy]/[isImprint] match only the path. So before
  // the doc viewer (which trusts its URL: no allow-list) may load a scanned value,
  // require the launcher apex over https with no embedded credentials, mirroring the
  // manifest's legal App Link filter. Returns the URL to open (locale variants like
  // /en/privacy pass through as-is), or null when it's not a legal page.
  fun scannedLegalUrl(raw: String): String? {
    val uri = runCatching { Uri.parse(raw) }.getOrNull() ?: return null
    if (!"https".equals(uri.scheme, ignoreCase = true) || !uri.userInfo.isNullOrEmpty()) return null
    if (!uri.host.equals(LAUNCHER_HOST, ignoreCase = true)) return null
    return raw.takeIf { isPrivacy(it) || isImprint(it) }
  }
}
