package com.allion.skyray.core

import java.net.HttpURLConnection
import java.net.URL

/**
 * Downloads a subscription body. Redirects are followed by hand so a 3xx to a
 * non-http launcher link (hiddify://import/<url>) is unwrapped instead of failing.
 * Port of App/Services/SubscriptionFetcher.swift.
 */
object SubscriptionFetcher {
    class FetchException(message: String) : Exception(message)

    /** [headers] keys are lower-cased: panels are inconsistent about their casing. */
    data class Response(val body: String, val finalUrl: String, val headers: Map<String, String> = emptyMap())

    /** Panels commonly gate on a known client UA, so send one they recognise. */
    private const val USER_AGENT = "SkyRay/1.0 (Android) v2rayNG/1.9 Hiddify"
    private const val TIMEOUT_MILLIS = 30_000

    fun fetch(urlString: String, maxHops: Int = 6): Response {
        var current = urlString
        repeat(maxHops) {
            val connection = (URL(current).openConnection() as HttpURLConnection).apply {
                instanceFollowRedirects = false
                connectTimeout = TIMEOUT_MILLIS
                readTimeout = TIMEOUT_MILLIS
                setRequestProperty("User-Agent", USER_AGENT)
            }
            try {
                val status = connection.responseCode
                if (status in 300..399) {
                    val location = connection.getHeaderField("Location")
                        ?: throw FetchException("Redirect without a target.")
                    val absolute = runCatching { URL(URL(current), location).toString() }.getOrDefault(location)
                    current = SubscriptionLinkResolver.resolve(absolute)?.url
                        ?: throw FetchException("Unsupported redirect target: ${absolute.take(80)}")
                    return@repeat
                }
                if (status !in 200..299) throw FetchException("Subscription server returned HTTP $status.")
                val headers = connection.headerFields
                    .mapNotNull { (key, values) -> key?.lowercase()?.let { it to values.joinToString(", ") } }
                    .toMap()
                return Response(connection.inputStream.bufferedReader().readText(), current, headers)
            } finally {
                connection.disconnect()
            }
        }
        throw FetchException("Too many redirects.")
    }
}
