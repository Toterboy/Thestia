package com.thestia.app

import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.content.Context
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * MainActivity mit drei Zusatzaufgaben:
 *  1. FLAG_SECURE verhindert Screenshots und Screen-Recording (Privatsphäre:
 *     Keine Fotos/Chats anderer Nutzer via Screenshot teilbar).
 *  2. Transit Spark (v0.9.0): BLE-Advertising über einen nativen
 *     Platform-Channel ("thestia/transit_ble"). Bewusst KEIN Plugin:
 *     flutter_ble_peripheral 3.1.0 kompiliert mit dem aktuellen
 *     Kotlin-Setup nicht (Argument-Type-Mismatch im Plugin-Code) - der
 *     eigene Channel ist minimal, wartbar und dependency-frei.
 *     Scanning läuft separat über flutter_blue_plus.
 *  3. Play Integrity (v0.9.0, nur Play-Flavor): Channel "thestia/integrity"
 *     für App-/Geräte-Attestierung bei der Video-Verifizierung. Der
 *     eigentliche Helper liegt im Play-Source-Set und wird per
 *     Reflection aufgerufen (F-Droid baut ohne ihn).
 */
class MainActivity : FlutterActivity() {
    private val channelName = "thestia/transit_ble"
    private val integrityChannelName = "thestia/integrity"
    private var advertiser: android.bluetooth.le.BluetoothLeAdvertiser? = null
    private var advertiseCallback: AdvertiseCallback? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // FLAG_SECURE verhindert Screenshots und Screen-Recording.
        // Schützt die Privatsphäre: Keine Fotos/Chats anderer Nutzer
        // können via Screenshot unkontrolliert weitergegeben werden.
        // Ausnahme: Store-Screenshot-Builds (Manifest-Meta "allowScreenshots"
        // via THESTIA_ALLOW_SCREENSHOTS=true) - NUR für eigene
        // Play-Store-Bilder, niemals verteilen.
        if (!screenshotsAllowed()) {
            window.setFlags(
                WindowManager.LayoutParams.FLAG_SECURE,
                WindowManager.LayoutParams.FLAG_SECURE
            )
        }
    }

    private fun screenshotsAllowed(): Boolean {
        return try {
            val info = packageManager.getApplicationInfo(
                packageName,
                android.content.pm.PackageManager.GET_META_DATA
            )
            info.metaData?.getString("allowScreenshots") == "true" ||
                info.metaData?.getBoolean("allowScreenshots") == true
        } catch (_: Exception) {
            false
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startAdvertise" -> {
                    val token = call.argument<String>("token") ?: ""
                    // Jitter-Zyklus kommt aus Dart (transit_ble_privacy.dart).
                    // Default 30 s, falls ein alter Client den Wert nicht
                    // mitschickt - sonst wuerde dort der starre Takt laufen.
                    val cycleMs = call.argument<Int>("cycleMs") ?: 30_000
                    startAdvertise(token, cycleMs, result)
                }
                "stopAdvertise" -> {
                    stopAdvertise()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        // Play Integrity (v0.9.0, Manipulationsschutz): Der Helper liegt
        // im Play-Source-Set und existiert in F-Droid-Builds NICHT -
        // deshalb Reflection statt direktem Aufruf (kompiliert überall).
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            integrityChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestToken" -> requestIntegrityToken(call, result)
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Fordert ein Play-Integrity-Token an (nur Play-Flavor).
     * F-Droid/iOS/Fehler → error → Dart fällt auf manuelle Prüfung zurück.
     *
     * Flavor-Erkennung OHNE BuildConfig (ist per Default deaktiviert):
     * Existiert die Helper-Klasse (Play-Source-Set), läuft ein
     * Play-Build - sonst (F-Droid) sauber UNAVAILABLE.
     *
     * R8-Hinweis: Der Helper ist in proguard-rules.pro per -keep
     * geschützt (Originalname + Member). R8 löst Class.forName/
     * getMethod bei gehaltener Klasse in direkte Aufrufe auf - die
     * Reflection-Strings verschwinden deshalb aus dem Release-Dex,
     * der Aufrufpfad bleibt erhalten (Mapping prüfen).
     */
    private fun requestIntegrityToken(
        call: io.flutter.plugin.common.MethodCall,
        result: MethodChannel.Result
    ) {
        val nonce = call.argument<String>("nonce") ?: ""
        if (nonce.isEmpty()) {
            result.error("ARG", "nonce fehlt", null)
            return
        }
        try {
            val helper = Class.forName("com.thestia.app.PlayIntegrityHelper")
            val method = helper.getMethod(
                "requestToken",
                android.app.Activity::class.java,
                String::class.java,
                MethodChannel.Result::class.java
            )
            method.invoke(null, this, nonce, result)
        } catch (e: ClassNotFoundException) {
            try {
                result.error("UNAVAILABLE", "Nur in Play-Builds verfügbar", null)
            } catch (_: Exception) {
            }
        } catch (e: Exception) {
            try {
                result.error("UNAVAILABLE", "Integrity n/a", null)
            } catch (_: Exception) {
            }
        }
    }

    /**
     * Startet das BLE-Advertising ("WST1" + Token, Hersteller-ID 0xFFFF).
     *
     * WICHTIG: Bluetooth-Advertising ist ASYNCHRON - startAdvertising()
     * kehrt sofort zurück, Erfolg/Misserfolg kommen über den
     * [AdvertiseCallback]. Die alte Version meldete immer sofort "true",
     * sodass z. B. ADVERTISE_FAILED_DATA_TOO_LARGE (Paket > 31 Byte)
     * stilles Funkstille bedeutete ("0 in Reichweite" trotz Nachbar).
     * Deshalb wird [result] erst im Callback beantwortet.
     */
    /**
     * Jitter-Zyklus des Advertisings (v0.9.2). Die Verzoegerung kommt von
     * Dart (transit_ble_privacy.dart, dort getestet) - hier nur der Timer.
     */
    private var cycleHandler: android.os.Handler? = null
    private var cycleRunnable: Runnable? = null
    private var currentToken: String? = null

    private fun startAdvertise(
        token: String,
        cycleMs: Int,
        result: MethodChannel.Result
    ) {
        var replied = false
        fun reply(ok: Boolean) {
            if (!replied) {
                replied = true
                try {
                    result.success(ok)
                } catch (_: Exception) {
                }
            }
        }
        try {
            stopAdvertise()
            currentToken = token
            val manager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
            advertiser = manager.adapter?.bluetoothLeAdvertiser
            val adv = advertiser
            if (adv == null || token.length < 8) {
                reply(false)
                return
            }

            val data = AdvertiseData.Builder()
                .setIncludeDeviceName(false)
                .setIncludeTxPowerLevel(false)
                .addManufacturerData(0xFFFF, "WST1$token".toByteArray(Charsets.UTF_8))
                .build()
            val settings = AdvertiseSettings.Builder()
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                .setConnectable(false)
                .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
                .build()

            val callback = object : AdvertiseCallback() {
                override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
                    advertiseCallback = this
                    reply(true)
                    scheduleJitterRestart(cycleMs)
                }

                override fun onStartFailure(errorCode: Int) {
                    // Nach Rotation/Neustart kann der Stack noch laufen.
                    if (errorCode == ADVERTISE_FAILED_ALREADY_STARTED) {
                        advertiseCallback = this
                        reply(true)
                    } else {
                        android.util.Log.e(
                            "ThestiaTransit",
                            "Advertising fehlgeschlagen, Code: $errorCode"
                        )
                        // KEIN Zyklus planen: der Stack sendet nicht. Eine
                        // Neustart-Schleife wuerde hier nur Akku fressen.
                        reply(false)
                    }
                }
            }
            adv.startAdvertising(settings, data, callback)
            // Sicherheitsnetz: Kommt gar kein Callback, nicht ewig hängen
            // (Dart hat zusätzlich ein 10-s-Timeout).
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                reply(false)
            }, 8000)
        } catch (e: Exception) {
            reply(false)
        }
    }

    /**
     * Plant den naechsten Advertising-Neustart nach [delayMs].
     *
     * stopAdvertising + startAdvertising erzeugt eine Funkluecke in
     * variabler Laenge. Das bricht die sessionuebergreifend konstante Phase
     * des ~100-ms-Takts auf. Die Adresse selbst vergibt der Stack als
     * Resolvable Private Address - daran wird hier nichts geaendert.
     */
    private fun scheduleJitterRestart(delayMs: Int) {
        cancelJitterRestart()
        val token = currentToken ?: return
        if (token.isBlank()) return
        // Untergrenze: unter ~10 s ist der Neustart teurer als der
        // Erkenntnisgewinn, und der Stack braucht Luft.
        val delay = delayMs.coerceIn(10_000, 120_000)
        val handler = android.os.Handler(android.os.Looper.getMainLooper())
        cycleHandler = handler
        val runnable = object : Runnable {
            override fun run() {
                val advNow = advertiser
                val cbNow = advertiseCallback
                if (advNow == null || cbNow == null || currentToken == null) return
                try {
                    advNow.stopAdvertising(cbNow)
                    val data = AdvertiseData.Builder()
                        .setIncludeDeviceName(false)
                        .setIncludeTxPowerLevel(false)
                        .addManufacturerData(
                            0xFFFF,
                            "WST1$token".toByteArray(Charsets.UTF_8)
                        )
                        .build()
                    val settings = AdvertiseSettings.Builder()
                        .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                        .setConnectable(false)
                        .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
                        .build()
                    // Neuer Callback je Zyklus: derselbe Callback-Objekt
                    // kann nach stopAdvertising nicht wiederverwendet werden.
                    val next = object : AdvertiseCallback() {
                        override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
                            advertiseCallback = this
                            scheduleJitterRestart(
                                (delay * 0.8).toInt() + (delay * 0.4 * Math.random()).toInt()
                            )
                        }

                        override fun onStartFailure(errorCode: Int) {
                            if (errorCode != ADVERTISE_FAILED_ALREADY_STARTED) {
                                android.util.Log.e(
                                    "ThestiaTransit",
                                    "Jitter-Neustart fehlgeschlagen, Code: $errorCode"
                                )
                            }
                        }
                    }
                    advNow.startAdvertising(settings, data, next)
                } catch (e: Exception) {
                    android.util.Log.e("ThestiaTransit", "Jitter-Neustart: $e")
                }
            }
        }
        cycleRunnable = runnable
        handler.postDelayed(runnable, delay.toLong())
    }

    private fun cancelJitterRestart() {
        cycleRunnable?.let { cycleHandler?.removeCallbacks(it) }
        cycleRunnable = null
        cycleHandler = null
    }

    private fun stopAdvertise() {
        // Zyklus zuerst beenden - sonst startet der Handler nach dem
        // Stopp noch einmal und sendet weiter.
        cancelJitterRestart()
        currentToken = null
        try {
            val cb = advertiseCallback
            val adv = advertiser
            if (adv != null && cb != null) {
                adv.stopAdvertising(cb)
            }
        } catch (e: Exception) {
            // Best effort.
        } finally {
            advertiseCallback = null
        }
    }
}
