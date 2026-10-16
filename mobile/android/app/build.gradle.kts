plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "ng.com.stall.stall"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Same package as the Trusted Web Activity on Google Play (android/), so this app ships as an update to it.
        // It can never change once the app is on Google Play.
        applicationId = "ng.com.stall.app"
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

    // Release builds are signed with the Stall upload key from GitHub secrets (the same key as android/, see android/README.md).
    // Without it (local builds, preview builds), the debug key is used so the app still installs for testing.
    val ks = System.getenv("STALL_KEYSTORE_FILE")
    signingConfigs {
        if (ks != null) {
            create("upload") {
                storeFile = file(ks)
                storePassword = System.getenv("STALL_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("STALL_KEY_ALIAS")
                keyPassword = System.getenv("STALL_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (ks != null) signingConfigs.getByName("upload") else signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
