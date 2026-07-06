import java.util.Properties

plugins {
  alias(libs.plugins.android.application)
  alias(libs.plugins.aboutlibraries)
  alias(libs.plugins.compose.compiler)
  alias(libs.plugins.kotlin.serialization)
}

// Release signing is driven by a git-ignored `keystore.properties` at the android/ root
// (keys: storeFile, storePassword, keyAlias, keyPassword; see keystore.properties.example).
// When it's absent — debug-only checkouts, CI without secrets — the release build stays
// unsigned; sign it via Android Studio's "Generate Signed Bundle / APK" + Play App Signing.
val keystorePropsFile = rootProject.file("keystore.properties")
val keystoreProps = Properties().apply {
    if (keystorePropsFile.exists()) keystorePropsFile.inputStream().use { load(it) }
}

android {
    namespace = "com.couchgames.controller"
    compileSdk = 37
    defaultConfig {
        applicationId = "com.couchgames.controller"
        minSdk = 24
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    signingConfigs {
        if (keystorePropsFile.exists()) {
            create("release") {
                storeFile = keystoreProps.getProperty("storeFile")?.let { rootProject.file(it) }
                storePassword = keystoreProps.getProperty("storePassword")
                keyAlias = keystoreProps.getProperty("keyAlias")
                keyPassword = keystoreProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Present only when keystore.properties exists; otherwise null → unsigned build.
            signingConfig = signingConfigs.findByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures {
      compose = true
      aidl = false
      buildConfig = true
      shaders = false
    }

    packaging {
      resources {
        excludes += "/META-INF/{AL2.0,LGPL2.1}"
      }
    }

    testOptions {
      // Zero the device animation scales while instrumented tests run — sheets and
      // dialogs settle instantly instead of racing the screenshot capture.
      animationsDisabled = true
    }
}

kotlin {
    jvmToolchain(17)
}

// Attribution list generation. Only collect the release classpath (what actually
// ships — drops debug/test-only tooling like ui-tooling, ui-test-manifest), and
// merge duplicate artifacts that resolve to the same library.
aboutLibraries {
    collect {
        filterVariants.addAll("release")
    }
    library {
        duplicationMode = com.mikepenz.aboutlibraries.plugin.DuplicateMode.MERGE
        duplicationRule = com.mikepenz.aboutlibraries.plugin.DuplicateRule.SIMPLE
    }
}

dependencies {
  implementation(platform(libs.androidx.compose.bom))

  // Core Android dependencies
  implementation(libs.androidx.core.ktx)
  implementation(libs.androidx.lifecycle.runtime.ktx)
  implementation(libs.androidx.activity.compose)

  // QR scanning — in-app CameraX preview + bundled ML Kit barcode model. Bundled
  // (vs Play Services code scanner) so scanning works without Google Play Services
  // and without a first-use module download; see ScanScreen.kt.
  implementation(libs.androidx.camera.camera2)
  implementation(libs.androidx.camera.lifecycle)
  implementation(libs.androidx.camera.view)
  implementation(libs.androidx.camera.mlkit.vision)
  implementation(libs.mlkit.barcode.scanning)

  // Open-source license list (About screen)
  implementation(libs.aboutlibraries.compose.m3)

  // Arch Components
  implementation(libs.androidx.lifecycle.runtime.compose)

  // Compose
  implementation(libs.androidx.compose.ui)
  implementation(libs.androidx.compose.material3)
  implementation(libs.androidx.compose.material.icons.core)

  // Navigation
  implementation(libs.androidx.navigation3.ui)
  implementation(libs.androidx.navigation3.runtime)

  // WebView compat — document-start script injection for the legal viewer.
  implementation(libs.androidx.webkit)

  // Instrumented smoke test + store-screenshot capture (androidTest/StoreScreenshotTest.kt)
  androidTestImplementation(platform(libs.androidx.compose.bom))
  androidTestImplementation(libs.androidx.compose.ui.test.junit4)
  androidTestImplementation(libs.androidx.test.ext.junit)
  androidTestImplementation(libs.androidx.espresso.core)
}
