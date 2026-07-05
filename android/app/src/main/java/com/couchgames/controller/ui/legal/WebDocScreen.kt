package com.couchgames.controller.ui.legal

import android.content.Intent
import android.view.ViewGroup
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import com.couchgames.controller.ui.components.BackScaffold

// The page renders its own <h1> title (e.g. "DATENSCHUTZERKLÄRUNG"); in-app the
// nav bar already shows it, so hide the page copy to avoid the duplicate. Injected
// at document-start (below) so the heading never flashes before it's hidden.
private const val HIDE_HEADING_JS = """
  (function () {
    if (document.getElementById('cg-hide-heading')) return;
    var s = document.createElement('style');
    s.id = 'cg-hide-heading';
    s.textContent = '.legal-shell > h1{display:none !important;}';
    (document.head || document.documentElement).appendChild(s);
  })();
"""

// The legal pages are all served from this origin; scope the injected script to it.
private val LEGAL_ORIGINS = setOf("https://couch-games.com")

/**
 * A read-only in-app viewer for a hosted legal document (privacy / imprint). Kept
 * deliberately separate from the game-host WebView: there is no navigation
 * allow-list or JS bridge here — these are trusted first-party pages, loaded so
 * the documents stay reachable from within the app.
 *
 * Each screen shows exactly one document. Tapping the page's cross-link to the
 * other doc opens it as its own screen ([onOpenDoc]), so the system back button
 * returns here — no in-page history to walk.
 */
@Composable
fun WebDocScreen(
  url: String,
  privacyTitle: String,
  imprintTitle: String,
  onOpenDoc: (String) -> Unit,
  onBack: () -> Unit,
) {
  var loading by remember { mutableStateOf(true) }
  val title = if (LegalLinks.isImprint(url)) imprintTitle else privacyTitle

  BackScaffold(title = title, onBack = onBack) { innerPadding ->
    Box(Modifier.fillMaxSize().padding(innerPadding)) {
      AndroidView(
        modifier = Modifier.fillMaxSize(),
        factory = { ctx ->
          WebView(ctx).apply {
            layoutParams = ViewGroup.LayoutParams(
              ViewGroup.LayoutParams.MATCH_PARENT,
              ViewGroup.LayoutParams.MATCH_PARENT,
            )
            // JS drives the page's i18n (localizes to the device language); without
            // it the German fallback text still renders.
            settings.javaScriptEnabled = true
            // Harden: a legal page has no business touching local files.
            settings.allowFileAccess = false
            settings.allowContentAccess = false
            @Suppress("DEPRECATION")
            settings.allowFileAccessFromFileURLs = false
            @Suppress("DEPRECATION")
            settings.allowUniversalAccessFromFileURLs = false
            // Best-effort: hide the page's own heading before first paint. Falls
            // back to a post-load inject (brief flash) on WebViews that lack the
            // document-start feature.
            val hasDocumentStart =
              WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)
            if (hasDocumentStart) {
              WebViewCompat.addDocumentStartJavaScript(this, HIDE_HEADING_JS, LEGAL_ORIGINS)
            }
            webViewClient = object : WebViewClient() {
              override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                val target = request.url.toString()
                // A tap on the cross-link to the other legal doc opens it as its own
                // screen, so the system back button returns here. (The initial page
                // load isn't routed through here.) Everything else — external references
                // (e.g. the linked data-protection authority), the site's home link, and
                // non-web schemes like mailto:/tel: (which a WebView can't render and
                // would show an error page for) — is handed to the system app.
                if (LegalLinks.isPrivacy(target) || LegalLinks.isImprint(target)) {
                  onOpenDoc(target)
                  return true
                }
                runCatching { ctx.startActivity(Intent(Intent.ACTION_VIEW, request.url)) }
                return true
              }
              override fun onPageStarted(view: WebView?, url: String?, favicon: android.graphics.Bitmap?) {
                loading = true
              }
              override fun onPageFinished(view: WebView?, url: String?) {
                loading = false
                if (!hasDocumentStart) view?.evaluateJavascript(HIDE_HEADING_JS, null)
              }
            }
            loadUrl(url)
          }
        },
      )
      if (loading) {
        LinearProgressIndicator(Modifier.fillMaxWidth().align(Alignment.TopCenter))
      }
    }
  }
}
