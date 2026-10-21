package com.wrfcoin.wrfcoin_mobile

import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.Wearable
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.charset.StandardCharsets
import org.json.JSONObject

/** Forwards a minimal weather snapshot to every paired Wear OS node. */
class WearCompanionBridge {
    fun handle(call: MethodCall, result: MethodChannel.Result, activity: MainActivity) {
        if (call.method != "publishReading") {
            result.notImplemented()
            return
        }

        val pressureHpa = call.argument<Double>("pressureHpa")
        val capturedAt = call.argument<String>("capturedAt")
        if (pressureHpa == null || capturedAt == null) {
            result.error("invalid_payload", "pressureHpa and capturedAt are required", null)
            return
        }
        if (!pressureHpa.isFinite()) {
            result.error("invalid_payload", "pressureHpa must be finite", null)
            return
        }

        val payload = JSONObject()
            .put("pressureHpa", pressureHpa)
            .put("capturedAt", capturedAt)
            .toString()
            .toByteArray(StandardCharsets.UTF_8)
        val nodeClient = Wearable.getNodeClient(activity)
        val messageClient = Wearable.getMessageClient(activity)
        nodeClient.connectedNodes
            .addOnSuccessListener { nodes ->
                if (nodes.isEmpty()) {
                    result.success(0)
                } else {
                    val sends = nodes.map { node ->
                        messageClient.sendMessage(node.id, "/wrfcoin/latest-reading", payload)
                    }
                    Tasks.whenAllComplete(sends)
                        .addOnSuccessListener { completed ->
                            result.success(completed.count { it.isSuccessful })
                        }
                        .addOnFailureListener { error ->
                            result.error("wear_unavailable", error.message, null)
                        }
                }
            }
            .addOnFailureListener { error ->
                result.error("wear_unavailable", error.message, null)
            }
    }
}
