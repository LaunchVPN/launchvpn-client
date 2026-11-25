package com.launchvpn.app.pigeon

import java.util.concurrent.locks.ReentrantReadWriteLock
import kotlin.concurrent.read
import kotlin.concurrent.write
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import libXray.LibXray

/**
 * The App process's calls into libXray, made from blocking threads. The VPN
 * runs in :native. Measurements run side by side: libXray keeps them apart
 * from its managed core. Any other call, and anything passed to [exclusive],
 * waits for them and runs by itself, since those may change process-global
 * state.
 */
class CoreCalls(private val invokeCore: (String) -> String = LibXray::invoke) {
    private val lock = ReentrantReadWriteLock()

    fun invoke(requestJson: String): Result<String> {
        val call = { runCatching { invokeCore(requestJson) } }
        return if (isMeasurement(requestJson)) lock.read(call) else lock.write(call)
    }

    fun <T> exclusive(block: () -> T): T = lock.write(block)

    private fun isMeasurement(requestJson: String): Boolean = try {
        JsonTool.json.decodeFromString<InvokeMethod>(requestJson).method == LibXrayMethod.PING_BATCH
    } catch (_: SerializationException) {
        false
    } catch (_: IllegalArgumentException) {
        false
    }

    @Serializable
    private data class InvokeMethod(val method: LibXrayMethod? = null)
}
