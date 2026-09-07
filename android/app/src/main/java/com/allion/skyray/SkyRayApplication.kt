package com.allion.skyray

import android.app.Application
import java.io.File

class SkyRayApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        extractGeoData()
    }

    /** Copies the trimmed geoip.dat/geosite.dat (bundled as assets, same files
     * used by the iOS build) to internal storage. SkyRayVpnService points
     * Xray at this directory via RaycoreBridge.setEnv() right before it
     * starts the tunnel (see that call site for why Os.setenv() alone
     * doesn't work here). */
    private fun extractGeoData() {
        val dir = File(filesDir, "geo").apply { mkdirs() }
        for (name in listOf("geoip.dat", "geosite.dat")) {
            val out = File(dir, name)
            if (out.exists()) continue
            runCatching {
                assets.open("geo/$name").use { input -> out.outputStream().use { input.copyTo(it) } }
            }
        }
    }
}
