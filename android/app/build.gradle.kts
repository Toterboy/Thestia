import java.util.Properties
import java.io.FileInputStream
import java.io.File

plugins {
    id("com.android.application")
    // Google-Services wird NICHT statisch angewendet (siehe unten) - nur
    // die "play"-Variante bekommt Firebase; die "fdroid"-Variante bleibt
    // komplett frei von proprietären Abhängigkeiten.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release-Signierung: woher die Passwörter kommen.
//
// DIE PASSWÖRTER LIEGEN NICHT MEHR IM PROJEKTORDNER (04.11.2026).
// Vorher standen sie im Klartext in android/key.properties - zwar
// gitignored, aber eben auf der Platte, in einem Ordner, der in
// Backups, Sync-Mappen und Screenshots mitschwimmt.
//
// DIE AUFLÖSUNG (in dieser Reihenfolge):
//
//   1. Umgebungsvariablen - der Weg für CI und für Build-Server:
//        THESTIA_KEYSTORE_PASSWORD, THESTIA_KEY_PASSWORD,
//        THESTIA_KEY_ALIAS, THESTIA_KEYSTORE_FILE
//   2. Eine Secret-Datei AUSSERHALB des Projekts:
//        %THESTIA_KEYSTORE_PROPERTIES% oder (Vorgabe)
//        %USERPROFILE%\.secrets\thestia-release.properties
//      bzw. ~/.secrets/thestia-release.properties
//   3. android/key.properties (Altlast, weiterhin unterstützt) -
//      enthält dann NUR noch keyAlias und storeFile.
//
// Wichtig: Es gibt KEINEN stillen Debug-Fallback. Fehlt die
// Konfiguration, schlägt der Release-Build FEHL - ein versehentlich
// debug-signiertes Release wäre nicht Play-Store-tauglich und
// sicherheitsrelevant. Für lokale Release-Testsignierungen explizit:
// -Pthestia.allowDebugSigning=true ODER Umgebungsvariable
// THESTIA_ALLOW_DEBUG_SIGNING=true.
val keystoreProperties = Properties()

// 1) Umgebungsvariablen (CI, Build-Server).
val envStorePassword = System.getenv("THESTIA_KEYSTORE_PASSWORD")
val envKeyPassword = System.getenv("THESTIA_KEY_PASSWORD")
val envKeyAlias = System.getenv("THESTIA_KEY_ALIAS")
val envStoreFile = System.getenv("THESTIA_KEYSTORE_FILE")

// 2) Secret-Datei außerhalb des Projektordners.
val secretFileFromEnv = System.getenv("THESTIA_KEYSTORE_PROPERTIES")
val defaultSecretFile = listOfNotNull(
    System.getProperty("user.home"),
    System.getenv("USERPROFILE"),
    System.getenv("HOME"),
).firstOrNull()?.let { home ->
    File(home, ".secrets/thestia-release.properties")
}
val secretPropertiesFile = secretFileFromEnv?.let { File(it) } ?: defaultSecretFile
if (secretPropertiesFile != null && secretPropertiesFile.isFile) {
    keystoreProperties.load(FileInputStream(secretPropertiesFile))
}

// 3) Altlast: android/key.properties.
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// Die Umgebungsvariablen haben Vorrang vor beiden Dateien.
fun secret(name: String, env: String?): String? =
    env ?: keystoreProperties.getProperty(name)?.takeIf { it.isNotBlank() }

val secretKeyAlias = secret("keyAlias", envKeyAlias)
val secretKeyPassword = secret("keyPassword", envKeyPassword)
val secretStorePassword = secret("storePassword", envStorePassword)
val secretStoreFile = secret("storeFile", envStoreFile)

// "Vorhanden" heisst: alle vier Angaben da. Nur dann wird signiert -
// sonst bricht der Release-Build (siehe unten) mit einer klaren
// Meldung ab.
val signingConfigured = secretKeyAlias != null &&
    secretKeyPassword != null &&
    secretStorePassword != null &&
    secretStoreFile != null

android {
    namespace = "com.thestia.app"
    // permission_handler_android (v14) benötigt compileSdk 37.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    signingConfigs {
        // Release-Signierung nur anlegen, wenn die Angaben VOLLSTAENDIG
        // sind; sonst greift in buildTypes der Debug-Fallback.
        if (signingConfigured) {
            create("release") {
                keyAlias = secretKeyAlias
                keyPassword = secretKeyPassword
                storeFile = secretStoreFile?.let { file(it) }
                storePassword = secretStorePassword
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
        // Screenshot-Freigabe NUR für Store-Screenshot-Builds: Über die
        // Umgebungsvariable THESTIA_ALLOW_SCREENSHOTS=true setzt der Build
        // ein Manifest-Flag, das FLAG_SECURE in MainActivity deaktiviert.
        // Standard (auch alle Store-Releases): false = Screenshots blockiert.
        manifestPlaceholders["allowScreenshots"] =
            (System.getenv("THESTIA_ALLOW_SCREENSHOTS") == "true").toString()
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 28

        // FEST auf 36, nicht `flutter.targetSdkVersion`.
        //
        // Google Play verlangt fuer neue Apps und Updates einen aktuellen
        // targetSdk; der Wert ist die hoechste API, deren Verhalten die
        // App ausdruecklich beherrscht. Mit dem Flutter-Default kam
        // automatisch die Version des jeweils installierten Flutter-SDK.
        // Das ist eine stille Abhaengigkeit: ein Flutter-Update aendert
        // die Play-Faehigkeit, ohne dass im Repository etwas zu sehen ist -
        // und genau so ist die targetSdk-Anforderung schon einmal
        // unterschritten worden.
        //
        // Beim Flutter-Upgrade pruefen: Ist die neue Version hoeher, wird
        // hier nachgezogen und die App gegen die neuen Pflichten geprueft.
        targetSdk = 36
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
            // Release mit dem echten Keystore signieren. Ohne vollständige
            // Signier-Angaben:
            //  - Ein echter Release-Build bricht hart FEHL (kein stiller
            //    Debug-Fallback - debug-signierte Releases waeren ein
            //    Sicherheitsrisiko).
            //  - Reine Debug-Builds (z. B. CI assembleFdroidDebug) konfigurieren
            //    den release-buildType mit, duerfen dadurch aber nicht knallen:
            //    Der Fehler wird nur geworfen, wenn tatsaechlich ein
            //    Release-Task angefragt wurde (Task-Name enthaelt "Release").
            if (signingConfigured) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                val allowDebugSigning =
                    System.getenv("THESTIA_ALLOW_DEBUG_SIGNING") == "true" ||
                        (project.findProperty("thestia.allowDebugSigning") as? String) == "true"
                val releaseRequested = gradle.startParameter.taskNames.any {
                    it.contains("Release", ignoreCase = true)
                }
                if (releaseRequested) {
                    if (allowDebugSigning) {
                        logger.warn("WARNUNG: Release wird mit dem DEBUG-Keystore signiert (nur für lokale Tests).")
                        signingConfig = signingConfigs.getByName("debug")
                    } else {
                        val secretFile = secretPropertiesFile?.absolutePath
                            ?: "(kein Secret-Dateipfad ermittelt)"
                        throw GradleException(
                            "Release-Build ohne Signier-Angaben nicht erlaubt. " +
                                "Setze THESTIA_KEYSTORE_PASSWORD/THESTIA_KEY_PASSWORD/THESTIA_KEY_ALIAS/" +
                                "THESTIA_KEYSTORE_FILE als Umgebungsvariablen, oder lege die Secret-Datei " +
                                "$secretFile an, oder trage keyAlias/storeFile in android/key.properties ein. " +
                                "Signiere lokal bewusst mit -Pthestia.allowDebugSigning=true."
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
