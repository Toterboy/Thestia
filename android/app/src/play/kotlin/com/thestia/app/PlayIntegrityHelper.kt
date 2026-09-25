package com.thestia.app

import android.app.Activity
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.IntegrityTokenRequest
import io.flutter.plugin.common.MethodChannel

/**
 * Play-Integrity-Token-Anfrage (v0.9.0, Manipulationsschutz).
 *
 * Liegt bewusst im PLAY-Source-Set (src/play): Die proprietäre
 * integrity-Bibliothek ist nur per playImplementation eingebunden und
 * landet NICHT in F-Droid-APKs. MainActivity ruft [requestToken] per
 * Reflection auf, damit der fdroid-Build ohne die Klasse kompiliert.
 *
 * Ablauf: Nonce kommt vom Dart-Code (Zufall pro Verifizierung), das
 * Token geht zurück an Dart und von dort an verify-account/action
 * "auto", wo der Server das Verdict bei Google prüft (App + Gerät
 * echt?). Fehler/fehlende Play-Dienste → error → Dart fällt auf die
 * manuelle Queue zurück (niemals Absturz, niemals Blockade).
 */
class PlayIntegrityHelper {
    companion object {
        @JvmStatic
        fun requestToken(
            activity: Activity,
            nonce: String,
            result: MethodChannel.Result
        ) {
            var replied = false
            fun replySuccess(token: String) {
                if (!replied) {
                    replied = true
                    try {
                        result.success(token)
                    } catch (_: Exception) {
                    }
                }
            }
            fun replyError(code: String, message: String) {
                if (!replied) {
                    replied = true
                    try {
                        result.error(code, message, null)
                    } catch (_: Exception) {
                    }
                }
            }
            try {
                val manager = IntegrityManagerFactory.create(activity)
                val request = IntegrityTokenRequest.builder()
                    .setNonce(nonce)
                    .build()
                manager.requestIntegrityToken(request)
                    .addOnSuccessListener { response ->
                        val token = response.token()
                        if (token.isNullOrEmpty()) {
                            replyError("EMPTY", "Leeres Integrity-Token")
                        } else {
                            replySuccess(token)
                        }
                    }
                    .addOnFailureListener { e ->
                        replyError(
                            "FAILED",
                            "Integrity-Anfrage fehlgeschlagen: ${e.message}"
                        )
                    }
                // Sicherheitsnetz: kein Callback → kein ewiges Hängen
                // (Dart hat zusätzlich ein Timeout).
                android.os.Handler(
                    android.os.Looper.getMainLooper()
                ).postDelayed({
                    replyError("TIMEOUT", "Integrity-Timeout")
                }, 20000)
            } catch (e: Exception) {
                replyError(
                    "UNAVAILABLE",
                    "Integrity n/a: ${e.message}"
                )
            }
        }
    }
}
