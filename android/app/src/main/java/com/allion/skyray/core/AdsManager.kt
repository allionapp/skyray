package com.allion.skyray.core

import android.app.Activity
import android.content.Context
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
        MobileAds.initialize(context) { loadAd(context) }
    }

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

    /** Shows the ad if one is ready and the cooldown has elapsed; always safe
     * to call right after a connection succeeds. */
    fun showAfterConnect(activity: Activity) {
        if (!didStart) return
        val now = System.currentTimeMillis()
        if (now - lastShownAtMillis < MIN_INTERVAL_MILLIS) return
        val ad = rewardedInterstitial ?: run {
            loadAd(activity.applicationContext)
            return
        }
        lastShownAtMillis = now
        // No in-app currency to grant; the reward just gates the ad's own close button.
        ad.show(activity) {}
    }
}
