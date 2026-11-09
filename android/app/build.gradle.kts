plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing comes only from these four variables. A release build never
// falls back to the debug key: a debug-signed APK cannot be upgraded by a
// properly signed one, so shipping it would strand every phone that installed it.
val releaseSigningEnvNames = listOf(
    "WRFCOIN_ANDROID_KEYSTORE_PATH",
    "WRFCOIN_ANDROID_KEYSTORE_PASSWORD",
    "WRFCOIN_ANDROID_KEY_ALIAS",
    "WRFCOIN_ANDROID_KEY_PASSWORD",
)
val releaseKeystorePath = providers.environmentVariable("WRFCOIN_ANDROID_KEYSTORE_PATH").orNull
val releaseKeystorePassword = providers.environmentVariable("WRFCOIN_ANDROID_KEYSTORE_PASSWORD").orNull
val releaseKeyAlias = providers.environmentVariable("WRFCOIN_ANDROID_KEY_ALIAS").orNull
val releaseKeyPassword = providers.environmentVariable("WRFCOIN_ANDROID_KEY_PASSWORD").orNull
val missingReleaseSigning = releaseSigningEnvNames.filter {
    providers.environmentVariable(it).orNull.isNullOrBlank()
}
val hasReleaseSigning = missingReleaseSigning.isEmpty()
// The compile-only dry run in docs/RELEASING.md builds an UNSIGNED release APK
// on purpose. It has to say so; it never gets the debug key either.
val allowUnsignedRelease =
    providers.environmentVariable("WRFCOIN_ANDROID_UNSIGNED_RELEASE").orNull == "1"

android {
    namespace = "com.wrfcoin.wrfcoin_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseKeystorePath!!)
                storePassword = releaseKeystorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.wrfcoin.wrfcoin_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Release builds use keystore material injected by GitHub Actions secrets
            // or the release owner's shell. Without it the release is unsigned, and
            // the check below refuses to build it unless the dry run asked for that.
            signingConfig = if (hasReleaseSigning) signingConfigs.getByName("release") else null
        }
    }
}

// Runs only when a release variant is built, so debug and profile builds are untouched.
tasks.matching { it.name == "preReleaseBuild" }.configureEach {
    doFirst {
        if (hasReleaseSigning) {
            val keystore = file(releaseKeystorePath!!)
            if (!keystore.isFile) {
                throw GradleException(
                    "RELEASE_SIGNING_REFUSED: WRFCOIN_ANDROID_KEYSTORE_PATH does not name a readable file.",
                )
            }
        } else if (!allowUnsignedRelease) {
            throw GradleException(
                "RELEASE_SIGNING_REFUSED: a release build needs all four signing variables " +
                    "and will not fall back to the debug key. Missing: " +
                    missingReleaseSigning.joinToString(", ") +
                    ". For the unsigned compile-only dry run set WRFCOIN_ANDROID_UNSIGNED_RELEASE=1; " +
                    "for a tester APK use scripts/build_profile_apk.sh.",
            )
        } else {
            logger.warn("WRFCOIN_ANDROID_UNSIGNED_RELEASE=1: building an UNSIGNED release. Do not install or distribute it.")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("com.google.android.gms:play-services-wearable:19.0.0")
    // Required by flutter_local_notifications ≥18 when targeting Java 17+
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // JVM tests of the Collect wake lock and alarms (src/test).
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.16")
    testImplementation("androidx.test:core:1.6.1")
}
