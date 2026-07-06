package com.couchgames.controller

import android.content.ContentValues
import android.graphics.Bitmap
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isDialog
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextClearance
import androidx.compose.ui.test.performTextInput
import androidx.test.core.app.ActivityScenario
import androidx.test.espresso.Espresso
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.couchgames.controller.data.Profile
import com.couchgames.controller.data.ProfileStore
import java.io.File
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Smoke test + store-screenshot capture in one pass: walks home → game info sheet →
 * profile sheet → manual code entry → About, asserting each screen's key content
 * (manifest load, live/soon status, name gating, version label) and saving a
 * full-device PNG per stop to shared storage (`Pictures/couchgames-screenshots`, via
 * MediaStore so no storage permission is needed).
 *
 * Shared storage outlives the automatic post-test uninstall, so CI simply
 * `adb pull /sdcard/Pictures/couchgames-screenshots` afterwards (and `rm -rf`s the
 * directory beforehand — MediaStore dedupes names as "x (1).png" across runs). The
 * flow deliberately avoids the QR scanner (camera) and never submits a room code —
 * nothing here depends on a live relay, so the test also runs offline.
 */
@RunWith(AndroidJUnit4::class)
class StoreScreenshotTest {

  @get:Rule val compose = createEmptyComposeRule()

  private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
  private val appContext get() = instrumentation.targetContext
  private lateinit var scenario: ActivityScenario<MainActivity>

  private fun str(id: Int, vararg args: Any): String = appContext.getString(id, *args)

  @Before
  fun launchWithFixedProfile() {
    // First launch mints a random FunnyName — pin the name BEFORE the activity starts
    // so assertions and store screenshots are deterministic.
    ProfileStore.save(appContext, Profile(PLAYER_NAME))
    scenario = ActivityScenario.launch(MainActivity::class.java)
  }

  @After
  fun tearDown() {
    scenario.close()
  }

  @Test
  fun storeFlow() {
    // ---- Home: catalog, live status, join card, profile chip ----
    waitForText("HexStacker")
    compose.onNodeWithText(str(R.string.app_name)).assertIsDisplayed()
    compose.onNodeWithText("HexStacker").assertIsDisplayed()
    compose.onNodeWithText("Tiny Track").assertExists()
    compose.onNodeWithText("Powder").assertExists()
    compose.onNodeWithText(str(R.string.status_live)).assertIsDisplayed()
    compose.onAllNodesWithText(str(R.string.status_coming_soon)).assertCountEquals(2)
    compose.onNodeWithText(str(R.string.join_title)).assertIsDisplayed()
    compose.onNodeWithText(str(R.string.scan_code)).assertIsDisplayed()
    compose.onNodeWithText(PLAYER_NAME).assertIsDisplayed()
    screenshot("01-home")

    // ---- Game info sheet: manifest copy + join actions for the live game ----
    compose.onNodeWithText("HexStacker").performClick()
    waitForText(str(R.string.game_hexstacker_players))
    compose.onNodeWithText(str(R.string.play_step_scan)).assertIsDisplayed()
    // Both the sheet and the home join card behind it carry the two join buttons.
    compose.onAllNodesWithText(str(R.string.scan_code)).assertCountEquals(2)
    compose.onAllNodesWithText(str(R.string.enter_code_manually)).assertCountEquals(2)
    // Give the muted gameplay trailer a moment to prepare and render real frames.
    Thread.sleep(2_000)
    screenshot("02-game-info")
    Espresso.pressBack()
    waitForTextGone(str(R.string.game_hexstacker_players))

    // ---- Profile sheet: blank-name gating + persistence round-trip ----
    compose.onNodeWithText(PLAYER_NAME).performClick()
    waitForText(str(R.string.name))
    val nameField = compose.onNode(hasSetTextAction())
    nameField.performTextClearance()
    compose.onNodeWithText(str(R.string.save)).assertIsNotEnabled()
    nameField.performTextInput(PLAYER_NAME)
    compose.onNodeWithText(str(R.string.save)).assertIsEnabled()
    screenshot("03-profile")
    compose.onNodeWithText(str(R.string.save)).performClick()
    waitForTextGone(str(R.string.save))
    compose.onNodeWithText(PLAYER_NAME).assertIsDisplayed()

    // ---- Manual code entry: empty-code gating; never submitted (no relay dependency) ----
    compose.onNodeWithText(str(R.string.enter_code_manually)).performClick()
    waitForText(str(R.string.enter_room_code))
    val playButton = compose.onNode(hasText(str(R.string.join)) and hasAnyAncestor(isDialog()))
    playButton.assertIsNotEnabled()
    compose.onNode(hasSetTextAction()).performTextInput("A3KX9p")
    playButton.assertIsEnabled()
    screenshot("04-enter-code")
    compose.onNodeWithText(str(R.string.cancel)).performClick()
    waitForTextGone(str(R.string.enter_room_code))

    // ---- About: legal hub reachable, version label present ----
    compose.onNodeWithContentDescription(str(R.string.about)).performClick()
    waitForText(str(R.string.privacy_policy))
    compose.onNodeWithText(str(R.string.imprint)).assertIsDisplayed()
    compose.onNodeWithText(str(R.string.open_source_licenses)).assertIsDisplayed()
    compose.onNodeWithText(str(R.string.version_label, BuildConfig.VERSION_NAME)).assertIsDisplayed()
    screenshot("05-about")
  }

  private fun waitForText(text: String) {
    compose.waitUntil(timeoutMillis = 10_000) {
      compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty()
    }
  }

  private fun waitForTextGone(text: String) {
    compose.waitUntil(timeoutMillis = 10_000) {
      compose.onAllNodesWithText(text).fetchSemanticsNodes().isEmpty()
    }
  }

  /** Full-device capture (system bars included) via UiAutomation — sheets and dialogs
   *  live in their own windows, which a compose-root capture would miss. */
  private fun screenshot(name: String) {
    compose.waitForIdle()
    Thread.sleep(400) // ripples, IME slide-in, window transitions
    val bitmap = requireNotNull(instrumentation.uiAutomation.takeScreenshot()) { "takeScreenshot returned null" }
    save(bitmap, name)
  }

  private fun save(bitmap: Bitmap, name: String) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      val values = ContentValues().apply {
        put(MediaStore.Images.Media.DISPLAY_NAME, "$name.png")
        put(MediaStore.Images.Media.MIME_TYPE, "image/png")
        put(MediaStore.Images.Media.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/$SHOT_DIR")
      }
      val resolver = appContext.contentResolver
      val uri = requireNotNull(resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)) {
        "MediaStore insert failed for $name"
      }
      resolver.openOutputStream(uri)!!.use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    } else {
      // Pre-Q fallback (dev devices only — CI runs API 35): app-private files.
      val dir = File(appContext.filesDir, SHOT_DIR).apply { mkdirs() }
      File(dir, "$name.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }
  }

  private companion object {
    const val PLAYER_NAME = "Alex"
    const val SHOT_DIR = "couchgames-screenshots"
  }
}
