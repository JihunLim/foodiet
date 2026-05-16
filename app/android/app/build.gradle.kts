plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.jihun.foodiet"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // `flutter_local_notifications` 가 요구하는 java.time API 백포트 (TimeZone 등)
        // 을 구버전 Android(21~25) 에서도 동작시키기 위한 core library desugaring.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.jihun.foodiet"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // Phase 3 에서 ProGuard/R8 keep 규칙 + minify 활성화 예정.
            // 그 전까지는 R8 이 reflection-heavy 한 google_mobile_ads / kakao_sdk
            // 클래스를 strip 해서 빌드가 깨지므로 명시적으로 꺼둔다.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // core library desugaring 런타임. flutter_local_notifications 2.x+ 가 요구함.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
