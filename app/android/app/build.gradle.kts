plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.mofox.android"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.mofox.android"
        // jniLibs 由 Android 解压到 nativeLibraryDir，该目录由系统打 exec 标，
        // 与 targetSdk 等级下的 SELinux W^X 限制兼容。所以可以正常追到 35。
        minSdk = 24
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
            // 只支持 arm64-v8a。32 位 ARM 装不了 napcat (Node.js)，x86 安卓没人用。
            abiFilters += listOf("arm64-v8a")
        }
        externalNativeBuild {
            cmake {
                arguments += listOf("-DANDROID_STL=none")
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
    }

    sourceSets {
        getByName("main") {
            jniLibs.srcDirs("src/main/jniLibs")
        }
    }

    // proot 的 loader / libtalloc / sudo 等带特殊符号或 setuid 标记，被 Gradle 默认 strip
    // 后会立刻挂掉。doNotStrip 必须覆盖所有 ABI 的全部 .so。
    packaging {
        jniLibs {
            useLegacyPackaging = true
            keepDebugSymbols += listOf(
                "**/libmofoxpty.so",
                "**/libbash.so",
                "**/libbusybox.so",
                "**/libproot.so",
                "**/libsudo.so",
                "**/libloader.so",
                "**/liblibtalloc.so.2.so",
            )
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
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
