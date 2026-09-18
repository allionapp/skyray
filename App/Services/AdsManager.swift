import AppTrackingTransparency
import GoogleMobileAds
import UIKit
import UserMessagingPlatform

/// Loads a Google AdMob rewarded-interstitial ad and shows it once after each
/// fresh connect (not on every reconnect/network blip). Handles Google's UMP
/// consent flow (GDPR/UK) and Apple's App Tracking Transparency prompt first,
/// since both must run before any ad request. Not used inside the tunnel
/// extension — this only runs in the main app.
@MainActor
final class AdsManager: NSObject, ObservableObject {
    static let shared = AdsManager()

    private var rewardedInterstitial: GADRewardedInterstitialAd?
    private var isLoadingAd = false
    private var didStart = false
    private var lastShown: Date?
    /// Cooldown so a flaky connection that drops and reconnects repeatedly
    /// doesn't show an ad every time.
    private let minInterval: TimeInterval = 20 * 60

    private override init() { super.init() }

    /// Call once at launch (skipped entirely in demo/screenshot mode by the caller).
    func start() {
        guard !didStart else { return }
        didStart = true
        let parameters = UMPRequestParameters()
        parameters.tagForUnderAgeOfConsent = false
        UMPConsentInformation.sharedInstance.requestConsentInfoUpdate(with: parameters) { [weak self] error in
            guard error == nil, let root = UIApplication.topMostViewController() else {
                self?.requestTrackingThenInitialize()
                return
            }
            UMPConsentForm.loadAndPresentIfRequired(from: root) { [weak self] _ in
                self?.requestTrackingThenInitialize()
            }
        }
    }

    private func requestTrackingThenInitialize() {
        ATTrackingManager.requestTrackingAuthorization { [weak self] _ in
            Task { @MainActor in self?.initializeAndLoad() }
        }
    }

    private func initializeAndLoad() {
        #if DEBUG
        GADMobileAds.sharedInstance().requestConfiguration.testDeviceIdentifiers = [GADSimulatorID]
        #endif
        GADMobileAds.sharedInstance().start(completionHandler: nil)
        loadAd()
    }

    private func loadAd() {
        guard !isLoadingAd, rewardedInterstitial == nil else { return }
        isLoadingAd = true
        GADRewardedInterstitialAd.load(withAdUnitID: AdsConfig.rewardedInterstitialUnitID, request: GADRequest()) { [weak self] ad, _ in
            self?.isLoadingAd = false
            self?.rewardedInterstitial = ad
            ad?.fullScreenContentDelegate = self
        }
    }

    /// Shows the ad if one is ready and the cooldown has elapsed; always safe
    /// to call right after a connection succeeds.
    ///
    /// [onAdSkipped] runs when an ad was shown but closed before it finished.
    /// Nothing is reported when no ad could be shown at all: a user whose
    /// network cannot even reach Google's ad servers must not lose the tunnel.
    /// Set while an ad is on screen: whether it ran to the end, and who to tell if it didn't.
    private var earnedReward = false
    private var skipHandler: (() -> Void)?
    private var isAdOnScreen = false
    /// A tap on the ad sends the user to the App Store, which also backgrounds
    /// the app; that is the advertiser's own call to action, not a walk-out.
    private var didClickAd = false

    func showAfterConnect(onAdSkipped: @escaping () -> Void) {
        guard didStart else { return }
        if let last = lastShown, Date().timeIntervalSince(last) < minInterval { return }
        guard let ad = rewardedInterstitial, let root = UIApplication.topMostViewController() else {
            loadAd()
            return
        }
        lastShown = Date()
        earnedReward = false
        didClickAd = false
        isAdOnScreen = true
        skipHandler = onAdSkipped
        // Watching it through is what keeps the connection, so the outcome of
        // this one showing has to be tracked, not just that it opened.
        ad.present(fromRootViewController: root) { [weak self] in
            self?.earnedReward = true
            NSLog("[ads] reward earned")
        }
    }
}

extension AdsManager {
    /// Leaving the app with the ad still up is how the free connection was had
    /// for nothing on iOS: nothing else notices, since the ad never dismisses.
    func appMovedToBackground() {
        guard isAdOnScreen, !earnedReward, !didClickAd, let handler = skipHandler else { return }
        skipHandler = nil
        NSLog("[ads] app left with the ad unfinished; the tunnel goes down")
        handler()
    }
}

extension AdsManager: GADFullScreenContentDelegate {
    func adDidRecordClick(_ ad: GADFullScreenPresentingAd) {
        didClickAd = true
    }

    func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        isAdOnScreen = false
        rewardedInterstitial = nil
        loadAd()
        // The reward can arrive just after the dismissal rather than before it,
        // and judging an ad skipped in that gap would drop a tunnel the user
        // had in fact paid for with their attention.
        let handler = skipHandler
        skipHandler = nil
        NSLog("[ads] ad dismissed, reward=\(earnedReward)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, !self.earnedReward else { return }
            NSLog("[ads] no reward after the grace period; the tunnel goes down")
            handler?()
        }
    }
    func ad(_ ad: GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        isAdOnScreen = false
        rewardedInterstitial = nil
        skipHandler = nil
        loadAd()
    }
}

private extension UIApplication {
    static func topMostViewController() -> UIViewController? {
        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?.rootViewController else { return nil }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        return top
    }
}
