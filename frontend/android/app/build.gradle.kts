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
            // R8 混淆与资源压缩。Flutter Gradle 插件在 release 构建默认注入
            // proguard-android-optimize.txt 与 flutter_proguard_rules.pro，并在
            // 本模块存在 proguard-rules.pro 时一并附加；这里显式声明同一策略，
            // 避免 `-Pshrink=false` 关掉插件默认后产物无声退回未混淆形态。
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    // ABI 拆分。默认 `flutter build apk` 需要 universal 的 app-release.apk，
    // 无条件开拆分会让工具按固定文件名找不到产物，因此与工具自身的
    // `--split-per-abi`（Gradle 属性 split-per-abi）联动，不擅自常开。
    val splitPerAbi = providers.gradleProperty("split-per-abi").orNull?.toBoolean() == true
    splits {
        abi {
            isEnable = splitPerAbi
            isUniversalApk = false
            if (splitPerAbi) {
                // 本项目只出 32/64 位 ARM。注意 Flutter 插件在 afterEvaluate
                // 阶段会 reset 并按目标平台重建 include 集合，实际生效集合以
                // 工具参数为准；这里记录的是项目的 ABI 意图声明。
                reset()
                include("armeabi-v7a")
                include("arm64-v8a")
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
