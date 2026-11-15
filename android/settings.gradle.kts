pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // AGP 9.1.1 (15.11.2026): Die aktualisierten Plugins (flutter_local_
    // notifications 23.x u. a.) ziehen androidx.core 1.19.0 - und dessen
    // AAR-Metadata verlangt AGP 9.1.0 oder neuer ("Dependency
    // 'androidx.core:core-ktx:1.19.0' requires Android Gradle plugin 9.1.0
    // or higher"). Mit 9.0.1 brach der Build genau daran ab
    // (checkPlayReleaseAarMetadata).
    //
    // AGP 9.1.1 verlangt seinerseits Gradle 9.3.1 - siehe
    // gradle/wrapper/gradle-wrapper.properties.
    id("com.android.application") version "9.1.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
    // Firebase (FCM-Transport für Supabase Push – kostenloses Firebase-Konto)
    id("com.google.gms.google-services") version "4.4.4" apply false
}

include(":app")
