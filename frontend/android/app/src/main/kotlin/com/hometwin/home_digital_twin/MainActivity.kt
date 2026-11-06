package com.hometwin.home_digital_twin

import android.content.Intent
import com.google.ar.core.ArCoreApk
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Flutter <-> native bridge for the ARCore room scanner.
 *   isSupported -> "supported" | "needs_install" | "checking" | "unsupported"
 *   startScan   -> JSON string (scan result) | null (user cancelled) | error
 */
class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> {
                    val a = ArCoreApk.getInstance().checkAvailability(this)
                    result.success(
                        when {
                            a.isSupported -> "supported"
                            a.isTransient -> "checking"
                            a == ArCoreApk.Availability.SUPPORTED_NOT_INSTALLED ||
                                a == ArCoreApk.Availability.SUPPORTED_APK_TOO_OLD -> "needs_install"
                            else -> "unsupported"
                        }
                    )
                }
                "startScan" -> {
                    if (pending != null) {
                        result.error("busy", "A scan is already in progress", null)
                    } else {
                        pending = result
                        startActivityForResult(Intent(this, ScanActivity::class.java), REQ_SCAN)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("FlutterActivity is a plain Activity; classic result API is fine here")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_SCAN) return
        val r = pending ?: return
        pending = null
        val json = data?.getStringExtra(ScanActivity.EXTRA_JSON)
        val err = data?.getStringExtra(ScanActivity.EXTRA_ERROR)
        when {
            resultCode == RESULT_OK && json != null -> r.success(json)
            err != null -> r.error("scan_failed", err, null)
            else -> r.success(null) // cancelled
        }
    }

    companion object {
        const val CHANNEL = "hometwin/room_scan"
        const val REQ_SCAN = 4711
    }
}