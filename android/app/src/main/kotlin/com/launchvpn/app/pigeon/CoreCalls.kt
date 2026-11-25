package com.launchvpn.app.pigeon

import java.util.concurrent.locks.ReentrantReadWriteLock
import kotlin.concurrent.read
import kotlin.concurrent.write
import libXray.LibXray
import org.json.JSONException
import org.json.JSONObject

/**
 * The App process's calls into libXray, made from blocking threads. The VPN
 * runs in :native. Measurements run side by side: libXray keeps them apart
 * from its managed core. Any other call, and anything passed to [alone], waits
 * for them and runs by itself, since those may change process-global state.
 */
class CoreCalls(private val invokeCore: (String) -> String = LibXray::invoke) {
    private val access = ReentrantReadWriteLock()

    fun invoke(requestJson: String): Result<String> {
        val call = { runCatching { invokeCore(requestJson) } }
        return if (isMeasurement(requestJson)) access.read(call) else access.write(call)
    }

    fun <T> alone(block: () -> T): T = access.write(block)

    private fun isMeasurement(requestJson: String): Boolean = try {
        JSONObject(requestJson).optString("method") == "pingBatch"
    } catch (_: JSONException) {
        false
    }
}
