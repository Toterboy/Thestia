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
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
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
                    startAdvertise(token, result)
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
    private fun startAdvertise(token: String, result: MethodChannel.Result) {
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
                }

                override fun onStartFailure(errorCode: Int) {
                    // Nach Rotation/Neustart kann der Stack noch laufen.
                    if (errorCode == ADVERTISE_FAILED_ALREADY_STARTED) {
                        advertiseCallback = this
                        reply(true)
                    } else {
                        android.util.Log.e(
                            "WispTransit",
                            "Advertising fehlgeschlagen, Code: $errorCode"
                        )
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

    private fun stopAdvertise() {
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
