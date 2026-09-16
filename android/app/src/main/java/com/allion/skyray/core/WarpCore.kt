package com.allion.skyray.core

import android.content.Context
import com.allion.skyray.data.AppConstants
import java.io.File

/**
 * Cloudflare WARP, run by the Aether core (AGPL-3.0, CluvexStudio/Aether).
 *
 * Aether ships as a native executable rather than a library, so it runs as a
 * child process the way Oblivion runs it, and exposes a local SOCKS5 proxy that
 * hev-socks5-tunnel dials — exactly the shape Xray and sing-box already have.
 *
 * Transports are tried in the order that a filtered network in Iran actually
 * allows: MASQUE over HTTP/2 looks like ordinary HTTPS and gets through, while
 * QUIC is dropped and plain WireGuard is throttled to a crawl.
 */
object WarpCore {
    /** One attempt: a label for the log and the flags that pick the transport. */
    private val TRANSPORTS = listOf(
        // turbo stops at the first gateway that answers. The default sweep keeps
        // collecting for its full two-minute budget before it connects at all,
        // which is far too long to sit behind a Connect button.
        "masque-h2" to listOf("--masque", "--h2", "--scan", "turbo"),
        "warp-in-warp" to listOf("--gool", "--scan", "turbo"),
        "wireguard" to listOf("--wg", "--scan", "turbo"),
    )

    private const val READY_MARKER = "socks5 server listening"
    private const val PER_TRANSPORT_TIMEOUT_MILLIS = 150_000L

    @Volatile private var process: Process? = null

    val isRunning: Boolean get() = process?.isAlive == true

    fun binary(context: Context): File = File(context.applicationInfo.nativeLibraryDir, "libaether.so")

    fun isSupported(context: Context): Boolean = binary(context).canExecute()

    /**
     * Starts WARP and returns the transport that worked, or throws with the last
     * error. [onLog] receives the core's own output for the tunnel log.
     */
    fun start(context: Context, onLog: (String) -> Unit): String {
        stop()
        val binary = binary(context)
        if (!binary.canExecute()) throw IllegalStateException("WARP is not available on this device")
        val dir = File(context.filesDir, "warp").apply { mkdirs() }

        var lastError = "WARP could not connect"
        for ((label, flags) in TRANSPORTS) {
            onLog("[warp] trying $label")
            val command = listOf(binary.absolutePath) + flags + listOf(
                "-4",
                "--bind", "127.0.0.1:${AppConstants.WARP_SOCKS_PORT}",
                "--config", File(dir, "aether.toml").absolutePath,
            )
            val started = runCatching {
                ProcessBuilder(command)
                    .directory(dir)
                    .redirectErrorStream(true)
                    .start()
            }.getOrElse {
                lastError = it.message ?: "could not start the WARP core"
                continue
            }
            process = started
            if (awaitReady(started, onLog)) {
                onLog("[warp] connected over $label")
                return label
            }
            lastError = "$label did not connect"
            stop()
        }
        throw IllegalStateException(lastError)
    }

    /** Reads the core's output until the proxy is up, it exits, or time runs out. */
    private fun awaitReady(process: Process, onLog: (String) -> Unit): Boolean {
        val deadline = System.currentTimeMillis() + PER_TRANSPORT_TIMEOUT_MILLIS
        val reader = process.inputStream.bufferedReader()
        var ready = false
        // The core keeps writing after it is up, so reading moves to a thread
        // once the proxy is listening; a full pipe would otherwise stall it.
        while (System.currentTimeMillis() < deadline) {
            val line = runCatching { reader.readLine() }.getOrNull() ?: break
            if (line.isNotBlank()) onLog(line.trim())
            if (line.contains(READY_MARKER)) { ready = true; break }
        }
        if (!ready) return false
        Thread {
            runCatching { reader.forEachLine { if (it.isNotBlank()) onLog(it.trim()) } }
        }.apply { isDaemon = true }.start()
        return true
    }

    fun stop() {
        process?.let { runCatching { it.destroyForcibly().waitFor() } }
        process = null
    }
}
