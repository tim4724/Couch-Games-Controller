package com.couchgames.controller.data

import android.content.Context
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

/**
 * On-demand download cache for gameplay trailers. Trailers are not bundled — they
 * would grow the install per game — so the info sheet shows cover art while the mp4
 * lands here, then plays from disk on every later open. Files live in cacheDir,
 * keyed by URL, so the OS reclaims them under storage pressure and a manifest URL
 * change simply fetches a new entry.
 */
object TrailerCache {
  /** Cached file for [url], downloading it first if absent. Blocking — call on IO. Null on any failure. */
  fun fetch(context: Context, url: String): File? {
    val dir = File(context.cacheDir, "trailers")
    dir.mkdirs()
    val key = MessageDigest.getInstance("SHA-256")
      .digest(url.toByteArray())
      .joinToString("") { "%02x".format(it) }
      .take(16)
    val file = File(dir, "$key.mp4")
    if (file.length() > 0) return file
    return runCatching {
      val conn = (URL(url).openConnection() as HttpURLConnection).apply {
        connectTimeout = 10_000
        readTimeout = 30_000
      }
      // Download to a unique temp sibling and rename, so a torn or concurrent
      // download can never be played.
      val tmp = File.createTempFile(key, ".part", dir)
      try {
        if (conn.responseCode != HttpURLConnection.HTTP_OK) return@runCatching null
        conn.inputStream.use { input -> tmp.outputStream().use { input.copyTo(it) } }
        if (tmp.renameTo(file) || file.length() > 0) file else null
      } finally {
        conn.disconnect()
        tmp.delete()
      }
    }.getOrNull()
  }
}
