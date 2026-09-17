package com.allion.skyray.core

import android.app.Activity
import android.content.Context
import com.allion.skyray.service.SkyRayVpnService
import com.google.android.gms.ads.AdRequest
import com.google.android.gms.ads.FullScreenContentCallback
import com.google.android.gms.ads.MobileAds
import com.google.android.gms.ads.rewardedinterstitial.RewardedInterstitialAd
import com.google.android.gms.ads.rewardedinterstitial.RewardedInterstitialAdLoadCallback
import com.google.android.ump.ConsentRequestParameters
import com.google.android.ump.UserMessagingPlatform

/**
 * Loads a Google AdMob rewarded-interstitial ad and shows it once after each
 * fresh connect (not on every reconnect/network blip). Handles Google's UMP
 * consent flow (GDPR/UK) first, since it must run before any ad request.
 * Mirrors App/Services/AdsManager.swift on iOS (there ATT gates the request
 * too; Android has no equivalent, so UMP consent is the only gate here).
 */
object AdsManager {
    private var rewardedInterstitial: RewardedInterstitialAd? = null
    private var isLoadingAd = false
    private var didStart = false
    private var lastShownAtMillis = 0L

    /** So a flaky connection that drops and reconnects repeatedly doesn't show an ad every time. */
    private const val MIN_INTERVAL_MILLIS = 20 * 60 * 1000L

    /** Call once at process start, from the main activity (UMP needs an Activity). */
    fun start(activity: Activity) {
        if (didStart) return
        didStart = true
        val appContext = activity.applicationContext
        val params = ConsentRequestParameters.Builder().build()
        val consentInfo = UserMessagingPlatform.getConsentInformation(activity)
        consentInfo.requestConsentInfoUpdate(
            activity,
            params,
            {
                UserMessagingPlatform.loadAndShowConsentFormIfRequired(activity) {
                    initializeAndLoad(appContext)
                }
            },
            { initializeAndLoad(appContext) },
        )
    }

    private fun initializeAndLoad(context: Context) {
        // Debug builds on the team's own phones get test ads, so development
        // never produces impressions or clicks AdMob would count as invalid.
        if (context.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0) {
            MobileAds.setRequestConfiguration(
                com.google.android.gms.ads.RequestConfiguration.Builder()
                    .setTestDeviceIds(TEST_DEVICE_IDS)
                    .build(),
            )
        }
        MobileAds.initialize(context) { loadAd(context) }
    }

    /** AdMob's hashed ids, as printed in logcat by the SDK on each device. */
    private val TEST_DEVICE_IDS = listOf(
        // AdMob rotates these per app install, so the phone keeps earning new
        // ids; each debug install prints its own in logcat.
        "07E1BE8FAC62500944093B6D767013B5", // Samsung Galaxy A17 (SM-A176U1)
        "185751BEA04B489B45EEFA10336D2AD3",
        "A58AAF34EF557B4CD3BC536159FD50D3",
    )

    private fun loadAd(context: Context) {
        if (isLoadingAd || rewardedInterstitial != null) return
        isLoadingAd = true
        RewardedInterstitialAd.load(
            context,
            AdsConfig.REWARDED_INTERSTITIAL_UNIT_ID,
            AdRequest.Builder().build(),
            object : RewardedInterstitialAdLoadCallback() {
                override fun onAdLoaded(ad: RewardedInterstitialAd) {
                    isLoadingAd = false
                    rewardedInterstitial = ad
                    ad.fullScreenContentCallback = object : FullScreenContentCallback() {
                        override fun onAdDismissedFullScreenContent() {
                            rewardedInterstitial = null
                            loadAd(context)
                        }
                        override fun onAdFailedToShowFullScreenContent(error: com.google.android.gms.ads.AdError) {
                            rewardedInterstitial = null
                            loadAd(context)
                        }
                    }
                }
                override fun onAdFailedToLoad(error: com.google.android.gms.ads.LoadAdError) {
                    isLoadingAd = false
                }
            },
        )
    }

    /**
     * Shows the ad if one is ready and the cooldown has elapsed; always safe to
     * call right after a connection succeeds.
     *
     * [onAdSkipped] runs when an ad was shown but closed before it finished.
     * Nothing is reported when no ad could be shown at all: a user whose
     * network cannot even reach Google's ad servers must not lose the tunnel
     * because of it.
     */
    fun showAfterConnect(activity: Activity, onAdSkipped: () -> Unit) {
        if (!didStart) return
        val now = System.currentTimeMillis()
        if (now - lastShownAtMillis < MIN_INTERVAL_MILLIS) return
        val ad = rewardedInterstitial ?: run {
            loadAd(activity.applicationContext)
            return
        }
        lastShownAtMillis = now
        val context = activity.applicationContext
        var earned = false
        // Watching it through is what keeps the connection, so the outcome of
        // this one showing has to be tracked, not just the fact that it opened.
        ad.fullScreenContentCallback = object : FullScreenContentCallback() {
            override fun onAdShowedFullScreenContent() {
                SkyRayVpnService.awaitingAdReward = true
            }
            override fun onAdDismissedFullScreenContent() {
                SkyRayVpnService.awaitingAdReward = false
                rewardedInterstitial = null
                loadAd(context)
                if (!earned) onAdSkipped()
            }
            override fun onAdFailedToShowFullScreenContent(error: com.google.android.gms.ads.AdError) {
                SkyRayVpnService.awaitingAdReward = false
                rewardedInterstitial = null
                loadAd(context)
            }
        }
        ad.show(activity) { earned = true }
    }
}
