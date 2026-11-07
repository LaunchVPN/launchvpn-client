package com.launchvpn.app.vpn

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import com.elvishew.xlog.XLog
import java.net.Inet4Address
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import libXray.DialerController
import libXray.LibXray

/**
 * The App's own traffic takes the tunnel, so a measurement this process takes
 * while VPN is on would describe the tunnel. Its temporary cores dial past the
 * tunnel instead, through the screen's [VpnStatusConnection], and resolve
 * server names through the network under it.
 */
object TunnelBypass : DialerController {
    private val connection = AtomicReference<VpnStatusConnection?>()
    private val registered = AtomicBoolean(false)

    /** The DNS server the core resolves through, or null for the system's. */
    private var resolver: String? = null

    /** The core keeps a registered controller for the life of the process. */
    fun attach(status: VpnStatusConnection) {
        connection.set(status)
        if (registered.compareAndSet(false, true)) LibXray.registerDialerController(this)
    }

    fun release(status: VpnStatusConnection) {
        connection.compareAndSet(status, null)
    }

    /** Without a screen nothing measures, so other dials go as they are. */
    override fun protectFd(fd: Long): Boolean = connection.get()?.protect(fd.toInt()) ?: true

    /**
     * The system resolves names through the tunnel while it runs, seconds
     * slower than the network under it. Before each core call, which the host
     * runs one at a time, the core resolves through that network's DNS while
     * VPN is on, and through the system's otherwise.
     */
    fun followTunnel(context: Context) {
        val server = if (VpnController.readVpnRunning(context)) underlyingDns(context) else null
        if (server == resolver) return
        try {
            if (server == null) LibXray.resetDNS() else LibXray.setDNS(this, server)
            resolver = server
        } catch (error: Exception) {
            XLog.e("Resolve past the tunnel failed", error)
        }
    }

    /** The first IPv4 DNS server of a network with internet that is not a VPN. */
    @Suppress("DEPRECATION") // One look per core call needs no network callback.
    private fun underlyingDns(context: Context): String? {
        val networks = context.getSystemService(ConnectivityManager::class.java) ?: return null
        for (network in networks.allNetworks) {
            val capabilities = networks.getNetworkCapabilities(network) ?: continue
            if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN) ||
                !capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            ) continue
            val dns = networks.getLinkProperties(network)?.dnsServers
                ?.firstOrNull { it is Inet4Address } ?: continue
            return "${dns.hostAddress}:53"
        }
        return null
    }
}
