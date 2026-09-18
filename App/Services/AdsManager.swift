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

    func showAfterConnect(onAdSkipped: @escaping () -> Void) {
        guard didStart else { return }
        if let last = lastShown, Date().timeIntervalSince(last) < minInterval { return }
        guard let ad = rewardedInterstitial, let root = UIApplication.topMostViewController() else {
            loadAd()
            return
        }
        lastShown = Date()
        earnedReward = false
        skipHandler = onAdSkipped
        // Watching it through is what keeps the connection, so the outcome of
        // this one showing has to be tracked, not just that it opened.
        ad.present(fromRootViewController: root) { [weak self] in
            self?.earnedReward = true
        }
    }
}

extension AdsManager: GADFullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        rewardedInterstitial = nil
        loadAd()
        let skipped = !earnedReward
        let handler = skipHandler
        skipHandler = nil
        if skipped { handler?() }
    }
    func ad(_ ad: GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
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
