package com.allion.skyray.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import androidx.core.app.NotificationCompat
import com.allion.skyray.MainActivity
import com.allion.skyray.R
import com.allion.skyray.core.RaycoreBridge
import com.allion.skyray.core.WarpCore
import com.allion.skyray.core.SingboxConfigBuilder
import com.allion.skyray.core.XrayConfigBuilder
import com.allion.skyray.data.AppConstants
import com.allion.skyray.data.AppSettings
import com.allion.skyray.data.CoreKind
import com.allion.skyray.data.ProfileStore
import com.allion.skyray.data.ServerProfile
import hev.htproxy.TProxyService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import libXray.DialerController
import libXray.LibXray
import java.io.File

/**
 * The VPN itself: establishes the TUN interface, hands its fd to
 * hev-socks5-tunnel (native, JNI), and runs Xray or sing-box in-process as
 * the SOCKS5 backend hev-socks5-tunnel forwards packets to. One process for
 * everything (unlike iOS's separate Network Extension), so no IPC is needed.
 */
class SkyRayVpnService : VpnService() {
    companion object {
        const val CHANNEL_ID = "skyray_vpn"
        const val NOTIF_ID = 1
        const val TUNNEL_IPV4 = "198.18.0.1"
        const val TUNNEL_IPV6 = "fd00:ffff::1"
        const val MTU = 1500

        @Volatile var isRunning: Boolean = false
            private set
        @Volatile var lastError: String? = null
            private set
        @Volatile var connectedAtMillis: Long = 0L
            private set

        /** Bytes the tunnel has sent (upload) and received (download) since connect. */
        @Volatile var txBytes: Long = 0L
            private set
        @Volatile var rxBytes: Long = 0L
            private set
    }

    private var tunFd: ParcelFileDescriptor? = null
    private val scope = CoroutineScope(Dispatchers.IO + Job())
    private var statsJob: Job? = null
    private lateinit var store: ProfileStore

    private val dialerController = object : DialerController {
        override fun protectFd(p0: Long): Boolean = protect(p0.toInt())
    }

    override fun onCreate() {
        super.onCreate()
        store = ProfileStore.get(this)
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            AppConstants.VPN_ACTION_DISCONNECT -> {
                stopTunnel()
                return START_NOT_STICKY
            }
            AppConstants.VPN_ACTION_CONNECT -> {
                val outboundJson = intent.getStringExtra(AppConstants.EXTRA_OUTBOUND_JSON)
                val coreName = intent.getStringExtra(AppConstants.EXTRA_CORE) ?: CoreKind.xray.name
                if (outboundJson != null) {
                    startTunnel(outboundJson, runCatching { CoreKind.valueOf(coreName) }.getOrDefault(CoreKind.xray))
                }
            }
        }
        return START_STICKY
    }

    private fun startTunnel(outboundJson: String, core: CoreKind) {
        if (isRunning) stopTunnel()
        lastError = null
        try {
            val settings = store.loadSettings()
            startForeground(NOTIF_ID, buildNotification())

            LibXray.registerDialerController(dialerController)

            val geoDir = File(filesDir, "geo")
            RaycoreBridge.setEnv("XRAY_LOCATION_ASSET", geoDir.absolutePath)
            val hasGeoData = File(geoDir, "geoip.dat").exists()
            // WARP runs its own core and proxy; the others are built here.
            val socksPort = if (core == CoreKind.warp) AppConstants.WARP_SOCKS_PORT else AppConstants.SOCKS_PORT
            when (core) {
                CoreKind.warp -> {
                    val transport = WarpCore.start(this) { line -> store.appendTunnelLog(line) }
                    store.appendTunnelLog("WARP ready over $transport")
                }
                CoreKind.xray -> {
                    val config = XrayConfigBuilder.runtimeConfig(outboundJson, settings, AppConstants.SOCKS_PORT, hasGeoData)
                    RaycoreBridge.testXrayConfig(config)
                    RaycoreBridge.runXray(config)
                }
                CoreKind.singbox -> {
                    val config = SingboxConfigBuilder.runtimeConfig(outboundJson, settings, AppConstants.SOCKS_PORT)
                    RaycoreBridge.testSingboxConfig(config)
                    RaycoreBridge.singboxStart(config)
                }
            }

            val builder = Builder()
                .setSession(AppConstants.VPN_DISPLAY_NAME)
                .setMtu(MTU)
                .addAddress(TUNNEL_IPV4, 24)
                .addAddress(TUNNEL_IPV6, 126)
                .addRoute("0.0.0.0", 0)
                .addRoute("::", 0)
                .addDnsServer("1.1.1.1")
                .addDnsServer("8.8.8.8")
                .setBlocking(false)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                builder.setMetered(false)
            }
            // Exclude our own app from the tunnel: not strictly required since we
            // protect() the core's own sockets, but avoids self-loops from any
            // stray connection (e.g. the in-app latency test).
            runCatching { builder.addDisallowedApplication(packageName) }

            val pfd = builder.establish() ?: throw IllegalStateException("VpnService.Builder.establish() returned null")
            tunFd = pfd

            val yaml = buildHevYaml(socksPort)
            val configFile = File(cacheDir, "hev-tunnel.yml").apply { writeText(yaml) }
            val started = TProxyService.TProxyStartService(configFile.absolutePath, pfd.fd)
            if (!started) throw IllegalStateException("hev-socks5-tunnel failed to start")

            isRunning = true
            connectedAtMillis = System.currentTimeMillis()
            store.appendTunnelLog("Connected via ${core.name}")
            startStatsLoop()
        } catch (e: Exception) {
            lastError = e.message ?: "Failed to connect"
            store.appendTunnelLog("ERROR ${e.message}")
            stopTunnel()
        }
    }

    private fun buildHevYaml(socksPort: Int): String = """
        tunnel:
          mtu: $MTU
          ipv4: $TUNNEL_IPV4
          ipv6: '$TUNNEL_IPV6'
        socks5:
          port: $socksPort
          address: 127.0.0.1
          udp: 'udp'
        misc:
          task-stack-size: 86016
          tcp-buffer-size: 65536
          max-session-count: 512
          connect-timeout: 5000
          tcp-read-write-timeout: 300000
          udp-read-write-timeout: 60000
          limit-nofile: 65535
          log-level: warn
    """.trimIndent()

    private fun startStatsLoop() {
        statsJob?.cancel()
        statsJob = scope.launch {
            while (isRunning) {
                val stats = currentStats()
                if (stats.size >= 4) {
                    txBytes = stats[1]
                    rxBytes = stats[3]
                }
                delay(1000)
            }
        }
    }

    fun currentStats(): LongArray = runCatching { TProxyService.TProxyGetStats() }.getOrDefault(LongArray(4))

    private fun stopTunnel() {
        WarpCore.stop()
        statsJob?.cancel()
        runCatching { TProxyService.TProxyStopService() }
        runCatching { RaycoreBridge.stopXray() }
        runCatching { RaycoreBridge.singboxStop() }
        runCatching { tunFd?.close() }
        tunFd = null
        isRunning = false
        connectedAtMillis = 0
        txBytes = 0
        rxBytes = 0
        store.appendTunnelLog("Disconnected")
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        stopTunnel()
        super.onDestroy()
    }

    override fun onRevoke() {
        stopTunnel()
        super.onRevoke()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            if (manager.getNotificationChannel(CHANNEL_ID) == null) {
                manager.createNotificationChannel(
                    NotificationChannel(CHANNEL_ID, "SkyRay VPN", NotificationManager.IMPORTANCE_LOW),
                )
            }
        }
    }

    private fun buildNotification(): Notification {
        val openIntent = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(AppConstants.VPN_DISPLAY_NAME)
            .setContentText("Connected")
            .setContentIntent(openIntent)
            .setOngoing(true)
            // Android 12+ defers a foreground-service notification by up to 10s
            // by default; VPN status must be visible to the user immediately.
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    /** Called from ShareLinkParser-style profile setup before starting the tunnel. */
    fun profileFor(id: String): ServerProfile? = store.loadProfiles().firstOrNull { it.id == id }
}
