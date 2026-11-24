import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}
val allowDebugFallback = project.findProperty("allowDebugReleaseSigning")?.toString()?.toBoolean() == true

android {
    namespace = "com.furniflow.erp"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // لتوزيع نسخة تجارية مستقلة على متجر Google Play، يمكنك تغيير applicationId إلى معرّفك الخاص
        applicationId = "com.furniflow.erp"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                val storeFilePath = keystoreProperties.getProperty("storeFile")
                    ?: throw GradleException("Missing storeFile in android/key.properties")
                storeFile = file(storeFilePath)
                storePassword = keystoreProperties.getProperty("storePassword")
                    ?: throw GradleException("Missing storePassword in android/key.properties")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                    ?: throw GradleException("Missing keyAlias in android/key.properties")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                    ?: throw GradleException("Missing keyPassword in android/key.properties")
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            } else if (allowDebugFallback) {
                signingConfig = signingConfigs.getByName("debug")
            } else {
                throw GradleException(
                    "Release keystore (android/key.properties) is required for commercial release builds! " +
                    "Copy android/key.properties.example to android/key.properties and configure your keystore, " +
                    "or pass -PallowDebugReleaseSigning=true for local testing only."
                )
            }
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
