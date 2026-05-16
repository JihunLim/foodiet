import java.util.Properties
import java.io.FileInputStream
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Firebase: google-services.json 파싱 + 빌드시 리소스 주입.
    id("com.google.gms.google-services")
}

// Release upload keystore 정보. `android/key.properties` 는 .gitignore.
// 개발자/CI 마다 별도로 두며, 파일이 없으면 release 빌드가 debug 키로 폴백.
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) load(FileInputStream(f))
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

    kotlin {
        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_17)
        }
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

    signingConfigs {
        // upload keystore 가 있으면 release 서명. 없으면 release block 에서 debug 로 폴백.
        if (rootProject.file("key.properties").exists()) {
            create("release") {
                storeFile = keystoreProperties["storeFile"]?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String?
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")
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
