import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // Google-Services wird NICHT statisch angewendet (siehe unten) - nur
    // die "play"-Variante bekommt Firebase; die "fdroid"-Variante bleibt
    // komplett frei von proprietären Abhängigkeiten.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release-Signierung über android/key.properties (NICHT committen – steht in
// .gitignore). Enthält keyAlias, keyPassword, storeFile, storePassword.
// Fehlt die Datei, schlägt der Release-Build FEHL (kein stiller Debug-
// Keystore-Fallback mehr – ein versehentlich debug-signiertes Release wäre
// nicht Play-Store-tauglich und sicherheitsrelevant). Für lokale Release-
// Testsignierungen explizit: -PWisp.allowDebugSigning=true ODER
// Umgebungsvariable WISP_ALLOW_DEBUG_SIGNING=true.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.thestia.app"
    // permission_handler_android (v14) benötigt compileSdk 37.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    signingConfigs {
        // Release-Signierung nur anlegen, wenn key.properties existiert;
        // sonst greift in buildTypes der Debug-Fallback.
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = keystoreProperties["storeFile"]?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.thestia.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 28
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Ohne --flavor wird die "play"-Variante gebaut (Firebase aktiv) -
        // der normale Entwicklungsflow bleibt damit unverändert.
        missingDimensionStrategy("distribution", "play")
    }

    flavorDimensions += "distribution"
    productFlavors {
        create("play") {
            dimension = "distribution"
            // Google Play: Firebase/FCM aktiv (google-services.json).
        }
        create("fdroid") {
            dimension = "distribution"
            // F-Droid: KEIN Firebase, kein google-services-Plugin.
            // Push optional später via UnifiedPush.
        }
    }

    buildTypes {
        release {
            // R8-Verkleinerung + Obfuskierung (explizit, war bisher schon
            // implizit aktiv - siehe mapping/ nach Release-Builds).
            // Eigene Keep-Regeln in proguard-rules.pro (v0.9.0: hält die
            // per Reflection geladene PlayIntegrityHelper-Klasse).
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            // Release mit dem echten Keystore signieren. Ohne key.properties:
            //  - Ein echter Release-Build bricht hart FEHL (kein stiller
            //    Debug-Fallback - debug-signierte Releases waeren ein
            //    Sicherheitsrisiko).
            //  - Reine Debug-Builds (z. B. CI assembleFdroidDebug) konfigurieren
            //    den release-buildType mit, duerfen dadurch aber nicht knallen:
            //    Der Fehler wird nur geworfen, wenn tatsaechlich ein
            //    Release-Task angefragt wurde (Task-Name enthaelt "Release").
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                val allowDebugSigning =
                    System.getenv("WISP_ALLOW_DEBUG_SIGNING") == "true" ||
                        (project.findProperty("wisp.allowDebugSigning") as? String) == "true"
                val releaseRequested = gradle.startParameter.taskNames.any {
                    it.contains("Release", ignoreCase = true)
                }
                if (releaseRequested) {
                    if (allowDebugSigning) {
                        logger.warn("WARNUNG: Release wird mit dem DEBUG-Keystore signiert (nur für lokale Tests).")
                        signingConfig = signingConfigs.getByName("debug")
                    } else {
                        throw GradleException(
                            "Release-Build ohne android/key.properties nicht erlaubt. " +
                                "Lege android/key.properties an (siehe README/.env.example) oder " +
                                "signiere lokal bewusst mit -PWisp.allowDebugSigning=true."
                        )
                    }
                }
                // Sonst (Debug-Build): bewusst KEINE Signierung setzen.
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Play Integrity NUR im Play-Flavor (v0.9.0, Manipulationsschutz):
    // Proprietäre Google-Bibliothek - darf NICHT in F-Droid-APKs landen
    // (F-Droid-Konformität). add() mit String statt playImplementation-
    // Accessor (Kotlin-DSL erzeugt ihn unter AGP 9 nicht). Der
    // Kotlin-Helfer liegt im Play-Source-Set (src/play), MainActivity
    // ruft ihn per Reflection (fdroid-sicher).
    add("playImplementation", "com.google.android.play:integrity:1.4.0")
}

// Konfliktlösung: androidx.credentials zieht JVM-tink, unifiedpush_android
// tink-android - identische Klassen in zwei Jars. Die JVM-Variante fliegt
// raus, die neuere Android-Variante wird erzwungen.
configurations.all {
    exclude(group = "com.google.crypto.tink", module = "tink")
    resolutionStrategy {
        force("com.google.crypto.tink:tink-android:1.23.0")
    }
}

flutter {
    source = "../.."
}

// Google-Services für ALLE Varianten außer explizit "fdroid" anwenden
// (Default-Entwicklungsflow = play). Erkennung über die von Flutter/Gradle
// übergebenen Task-Namen (assemblePlay*, assembleFdroid*, ...).
val tasksRequested = gradle.startParameter.taskNames.joinToString(" ")
val isFdroidBuild = tasksRequested.contains("fdroid", ignoreCase = true)
if (!isFdroidBuild) {
    apply(plugin = "com.google.gms.google-services")
}
