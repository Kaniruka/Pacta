import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing sources. Each value is read from `android/key.properties`
// first (generated locally by `python scripts/pacta_build.py init-keystore`
// and git-ignored), then from the environment variables that
// `.github/workflows/release.yml` restores from repository secrets. Relative
// `storeFile` values resolve against this module (`android/app/`), which is the
// shape `init-keystore` writes.
val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties().apply {
    if (keyPropertiesFile.isFile) {
        keyPropertiesFile.inputStream().use { stream -> load(stream) }
    }
}

fun signingValue(fileKey: String, environmentKey: String): String? {
    val fromFile = keyProperties.getProperty(fileKey)?.trim().orEmpty()
    if (fromFile.isNotEmpty()) {
        return fromFile
    }
    val fromEnvironment = System.getenv(environmentKey)?.trim().orEmpty()
    return fromEnvironment.ifEmpty { null }
}

val releaseStoreFile = file(
    signingValue("storeFile", "ANDROID_KEYSTORE_PATH") ?: "upload-keystore.jks"
)
val releaseStorePassword = signingValue("storePassword", "ANDROID_KEYSTORE_PASSWORD")
val releaseKeyAlias = signingValue("keyAlias", "ANDROID_KEY_ALIAS")
val releaseKeyPassword = signingValue("keyPassword", "ANDROID_KEY_PASSWORD")
val releaseSigningReady = releaseStoreFile.isFile &&
    !releaseStorePassword.isNullOrEmpty() &&
    !releaseKeyAlias.isNullOrEmpty() &&
    !releaseKeyPassword.isNullOrEmpty()

// `-PrequireReleaseSigning=true` or PACTA_REQUIRE_RELEASE_SIGNING=true (set by
// `scripts/pacta_build.py build --require-release-signing`) turns a missing
// signing configuration into a configuration-time failure instead of a silent
// debug-key release build.
val requireReleaseSigning =
    (findProperty("requireReleaseSigning") as String?)?.toBoolean() == true ||
        System.getenv("PACTA_REQUIRE_RELEASE_SIGNING")?.toBoolean() == true

android {
    namespace = "com.rukani.pacta"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        multiDexEnabled = true
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.rukani.pacta"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseSigningReady) {
            create("release") {
                storeFile = releaseStoreFile
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            // A real release signature when one is configured; otherwise the
            // debug key keeps `flutter run --release` working locally. Builds
            // produced with the fallback must never be distributed.
            signingConfig = if (releaseSigningReady) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

if (!releaseSigningReady) {
    val signingProblem = "Pacta release signing is not configured: " +
        "${releaseStoreFile.absolutePath} is missing or a password/keyAlias entry is empty. " +
        "Run `python scripts/pacta_build.py init-keystore`, or set ANDROID_KEYSTORE_PATH, " +
        "ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS and ANDROID_KEY_PASSWORD."
    if (requireReleaseSigning) {
        throw GradleException(
            "$signingProblem This build requires a real release signature " +
                "(requireReleaseSigning=true)."
        )
    }
    logger.warn(
        "$signingProblem Falling back to the debug signing key; never distribute this artifact."
    )
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
