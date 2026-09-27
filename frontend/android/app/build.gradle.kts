import org.gradle.api.GradleException

plugins {
    id("com.android.application")
    // Flutter Gradle 插件；Kotlin 由 AGP 9 Built-in Kotlin 提供。
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.omninest.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    val releaseKeystorePath = System.getenv("OMNINEST_ANDROID_KEYSTORE_PATH")
    val releaseKeystorePassword = System.getenv("OMNINEST_ANDROID_KEYSTORE_PASSWORD")
    val releaseKeyAlias = System.getenv("OMNINEST_ANDROID_KEY_ALIAS")
    val releaseKeyPassword = System.getenv("OMNINEST_ANDROID_KEY_PASSWORD")
    val allowDebugReleaseSigning = System.getenv("OMNINEST_ALLOW_DEBUG_RELEASE_SIGNING")
        ?.equals("true", ignoreCase = true) == true
    val hasReleaseSigning = listOf(
        releaseKeystorePath,
        releaseKeystorePassword,
        releaseKeyAlias,
        releaseKeyPassword,
    ).all { !it.isNullOrBlank() }
    val releaseBuildRequested = gradle.startParameter.taskNames.any {
        it.contains("release", ignoreCase = true)
    }
    if (releaseBuildRequested && !hasReleaseSigning && !allowDebugReleaseSigning) {
        throw GradleException(
            "Android release 缺少正式签名配置；请设置 OMNINEST_ANDROID_KEYSTORE_PATH、" +
                "OMNINEST_ANDROID_KEYSTORE_PASSWORD、OMNINEST_ANDROID_KEY_ALIAS 和 " +
                "OMNINEST_ANDROID_KEY_PASSWORD。仅本地测量可显式设置 " +
                "OMNINEST_ALLOW_DEBUG_RELEASE_SIGNING=true。",
        )
    }

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.omninest.app"
        // 平台版本统一继承 Flutter 工具链配置。
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
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

    buildTypes {
        release {
            signingConfig = when {
                hasReleaseSigning -> signingConfigs.getByName("release")
                allowDebugReleaseSigning -> signingConfigs.getByName("debug")
                else -> null
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
