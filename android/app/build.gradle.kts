plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.arya"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    signingConfigs {
        create("pinned") {
            storeFile = rootProject.file("../debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.arya"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    packaging {
        jniLibs {
            // Only include arm64-v8a native libs (Samsung A53). Exclude all other ABIs.
            // This removes libflutter.so and libonnxruntime.so for armeabi-v7a, x86,
            // and x86_64, saving ~70MB from the debug APK.
            exclude("lib/armeabi-v7a/**")
            exclude("lib/x86/**")
            exclude("lib/x86_64/**")
            // Vulkan validation layer is a debug-only artifact, not needed at runtime.
            exclude("lib/arm64-v8a/libVkLayer_khronos_validation.so")
        }
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("pinned")
        }
        release {
            signingConfig = signingConfigs.getByName("pinned")
        }
    }
}

dependencies {
    implementation("androidx.documentfile:documentfile:1.0.1")
    implementation("androidx.media:media:1.7.0")
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.20.0")
}

flutter {
    source = "../.."
}
