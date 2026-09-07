package hev.htproxy

/**
 * JNI bridge to hev-socks5-tunnel (third_party/hev-socks5-tunnel), reused
 * unmodified from the iOS build's native code. The package/class name here
 * (hev.htproxy.TProxyService) must match the PKGNAME/CLSNAME macros baked
 * into src/hev-jni.c at build time (its defaults, left unchanged).
 */
object TProxyService {
    init {
        System.loadLibrary("hev-socks5-tunnel")
    }

    /** Starts the tunnel on a background thread; returns once it's running. */
    external fun TProxyStartService(configPath: String, fd: Int): Boolean
    external fun TProxyStopService(): Boolean
    external fun TProxyIsRunning(): Boolean

    /** [txPackets, txBytes, rxPackets, rxBytes]. */
    external fun TProxyGetStats(): LongArray
}
