package com.launchvpn.app.automation

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.elvishew.xlog.XLog
import com.launchvpn.app.R
import com.launchvpn.app.vpn.VpnController

/** Public adapter only. The existing VPN service remains the lifecycle owner. */
class VpnAutomationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (action != ACTION_START && action != ACTION_STOP) return
        val store = AutomationStore(context)
        @Suppress("DEPRECATION")
        val token = try { intent.extras?.get(EXTRA_TOKEN) } catch (_: RuntimeException) { null }
        if (!store.authorized(token)) return
        // A cold receiver can run before either the Activity or VPN service.
        XLog.init()

        try {
            if (action == ACTION_START) {
                if (store.startBlocked) {
                    fail(context, context.getString(R.string.automation_data_busy), false)
                } else if (VpnController.startSavedVpn(context, automation = true) != VpnController.SavedStartResult.STARTED) {
                    fail(context, VpnController.lastError, false)
                }
            } else if (!VpnController.stopVpn(context)) {
                fail(context, VpnController.lastError, true)
            }
        } catch (error: Exception) {
            XLog.e("VPN automation command failed", error)
            fail(context, error.message, action == ACTION_STOP)
        }
    }

    private fun fail(context: Context, reason: String?, stopping: Boolean) {
        XLog.w("VPN automation command rejected: ${reason ?: "unknown"}")
        VpnController.reportStartFailure(context, reason, showToast = false, stopping = stopping)
    }

    companion object {
        const val ACTION_START = "com.launchvpn.app.action.START_VPN"
        const val ACTION_STOP = "com.launchvpn.app.action.STOP_VPN"
        const val EXTRA_TOKEN = "token"
    }
}
