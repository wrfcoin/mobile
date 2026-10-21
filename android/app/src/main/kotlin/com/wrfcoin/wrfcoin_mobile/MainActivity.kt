package com.wrfcoin.wrfcoin_mobile

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.os.PersistableBundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// A FragmentActivity: local_auth can only show its biometric prompt from one
// (mobile#320). Under a plain FlutterActivity every prompt failed with
// uiUnavailable, so the wallet key could never be unlocked.
class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "com.wrfcoin.wrfcoin_mobile/screen_security"
    private val WEAR_CHANNEL = "com.wrfcoin.wrfcoin_mobile/wear_companion"
    private val CLIPBOARD_CHANNEL = "com.wrfcoin.wrfcoin_mobile/secure_clipboard"
    private val wearCompanionBridge = WearCompanionBridge()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enableScreenSecurity" -> {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        result.success(null)
                    }
                    "disableScreenSecurity" -> {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WEAR_CHANNEL)
            .setMethodCallHandler { call, result ->
                wearCompanionBridge.handle(call, result, this)
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CLIPBOARD_CHANNEL)
            .setMethodCallHandler { call, result ->
                val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                when (call.method) {
                    "copySensitive" -> {
                        val text = call.argument<String>("text")
                        val label = call.argument<String>("label")
                        if (text == null || label.isNullOrEmpty()) {
                            result.error("bad_args", "text and label are required", null)
                            return@setMethodCallHandler
                        }
                        val clip = ClipData.newPlainText(label, text)
                        // Keeps the text out of the clipboard preview and
                        // keyboard suggestions. The literal is the same key,
                        // honoured by some OEM clipboards before Android 13.
                        clip.description.extras = PersistableBundle().apply {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                                putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true)
                            } else {
                                putBoolean("android.content.extra.IS_SENSITIVE", true)
                            }
                        }
                        clipboard.setPrimaryClip(clip)
                        result.success(true)
                    }
                    "clearIfOurs" -> {
                        val label = call.argument<String>("label")
                        if (label.isNullOrEmpty()) {
                            result.error("bad_args", "label is required", null)
                            return@setMethodCallHandler
                        }
                        // Android 10+ hides the clipboard from an app without
                        // focus, so an empty answer then proves nothing: the
                        // caller retries on resume.
                        if (!hasWindowFocus()) {
                            result.success("unreadable")
                            return@setMethodCallHandler
                        }
                        // Compares only the label, so the text is never read
                        // back.
                        val description = clipboard.primaryClipDescription
                        when {
                            description == null -> result.success("notOurs")
                            description.label?.toString() != label -> result.success("notOurs")
                            else -> {
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                    clipboard.clearPrimaryClip()
                                } else {
                                    clipboard.setPrimaryClip(ClipData.newPlainText("", ""))
                                }
                                result.success("cleared")
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
