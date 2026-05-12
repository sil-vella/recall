import java.io.FileInputStream
import java.util.Base64
import java.util.Properties

/**
 * Flutter passes `--dart-define` keys to Gradle as a comma-separated list of
 * Base64-encoded `KEY=VALUE` tokens ([dart-defines] project property).
 * Used so `ADMOB_APPLICATION_ID` can live in repo `.env` / `.env.prod` like other AdMob vars.
 */
private fun decodeDartDefinesMap(raw: String?): Map<String, String> {
    if (raw.isNullOrBlank()) return emptyMap()
    val decoder = Base64.getDecoder()
    val out = mutableMapOf<String, String>()
    for (token in raw.split(',')) {
        val t = token.trim()
        if (t.isEmpty()) continue
        try {
            val decoded = String(decoder.decode(t), Charsets.UTF_8)
            val idx = decoded.indexOf('=')
            if (idx > 0 && idx < decoded.length - 1) {
                out[decoded.substring(0, idx)] = decoded.substring(idx + 1)
            }
        } catch (_: IllegalArgumentException) {
            // ignore malformed segment
        }
    }
    return out
}

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.reignofplay.dutch"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.reignofplay.dutch"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        val localProps = Properties()
        val localPropsFile = rootProject.file("local.properties")
        if (localPropsFile.exists()) {
            localPropsFile.inputStream().use { localProps.load(it) }
        }
        // Precedence: --dart-define ADMOB_APPLICATION_ID (from .env via launch/build scripts)
        // > android/local.properties admob.application_id > production app id (Dutch AdMob).
        val dartDefinesRaw =
            (project.findProperty("dart-defines") ?: project.rootProject.findProperty("dart-defines"))
                ?.toString()
        val fromDart = (decodeDartDefinesMap(dartDefinesRaw)["ADMOB_APPLICATION_ID"] ?: "").trim()
        val fromLocal = (localProps.getProperty("admob.application_id") ?: "").trim()
        // Default = Dutch production AdMob *app* id. If you use Google test *ad units* (ca-app-pub-3940256099942544/…),
        // you must pass ADMOB_APPLICATION_ID=ca-app-pub-3940256099942544~3347511713 via dart-define (.env.local).
        val admobAppId =
            when {
                fromDart.isNotEmpty() -> fromDart
                fromLocal.isNotEmpty() -> fromLocal
                else -> "ca-app-pub-6524100109992126~6470366151"
            }
        manifestPlaceholders["ADMOB_APPLICATION_ID"] = admobAppId
    }

    // Load keystore properties for release signing
    // Path: flutter_base_05/keystore.properties (from android/app/build.gradle.kts, go up 2 levels)
    val keystorePropertiesFile = file("../../keystore.properties")
    val keystoreProperties = Properties()
    if (keystorePropertiesFile.exists()) {
        keystoreProperties.load(FileInputStream(keystorePropertiesFile))
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                // Resolve keystore file path: upload-key.jks is in flutter_base_05/ (same dir as keystore.properties)
                val keystoreFileName = keystoreProperties["storeFile"] as String
                val keystoreFile = file("../../$keystoreFileName")
                if (keystoreFile.exists()) {
                    storeFile = keystoreFile
                    storePassword = keystoreProperties["storePassword"] as String
                } else {
                    println("WARNING: Keystore file not found: ${keystoreFile.absolutePath}")
                }
            }
        }
    }

    buildTypes {
        debug {
            // Use release keystore for debug builds too (so debug and release share same SHA-1)
            // This allows using the same OAuth client for both debug and release builds
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
            // If keystore.properties doesn't exist, fall back to default debug signing
        }
        release {
            // Use release keystore for production APKs
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                // Fallback to debug if keystore.properties not found
                signingConfig = signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
