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
    /// How long after a connect an ad that arrives late is still shown.
    private let showWindow: TimeInterval = 60

    /// Set by VPNManager: whether the tunnel is up and so carries this app's requests. No ad
    /// request leaves without it, so none goes to Google from the real network.
    var tunnelUp = false {
        didSet { if !tunnelUp { pendingShowUntil = nil; pendingSkipHandler = nil } }
    }

    /// A connect still waiting for its ad: shown when it arrives, within `showWindow`.
    private var pendingShowUntil: Date?
    private var pendingSkipHandler: (() -> Void)?

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
        guard tunnelUp, !isLoadingAd, rewardedInterstitial == nil else { return }
        isLoadingAd = true
        GADRewardedInterstitialAd.load(withAdUnitID: AdsConfig.rewardedInterstitialUnitID, request: GADRequest()) { [weak self] ad, _ in
            guard let self else { return }
            self.isLoadingAd = false
            self.rewardedInterstitial = ad
            ad?.fullScreenContentDelegate = self
            self.showPending()
        }
    }

    /// The ad the first connect was waiting for has arrived: shown if it is still in time.
    private func showPending() {
        guard let until = pendingShowUntil, let handler = pendingSkipHandler else { return }
        pendingShowUntil = nil
        pendingSkipHandler = nil
        guard tunnelUp, Date() < until, UIApplication.shared.applicationState == .active else { return }
        showAfterConnect(onAdSkipped: handler)
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
    private var backgroundObserver: NSObjectProtocol?
    /// A tap on the ad sends the user to the App Store, which also backgrounds
    /// the app; that is the advertiser's own call to action, not a walk-out.
    private var didClickAd = false

    func showAfterConnect(onAdSkipped: @escaping () -> Void) {
        guard didStart else { return }
        if let last = lastShown, Date().timeIntervalSince(last) < minInterval { return }
        guard let ad = rewardedInterstitial, let root = UIApplication.topMostViewController() else {
            // The SDK starts only now, over the tunnel, so the first ad is usually still on its
            // way: show it when it arrives.
            pendingShowUntil = Date().addingTimeInterval(showWindow)
            pendingSkipHandler = onAdSkipped
            loadAd()
            return
        }
        lastShown = Date()
        earnedReward = false
        didClickAd = false
        isAdOnScreen = true
        // SwiftUI's scenePhase does not reach a view the ad has covered, so the
        // notification is what tells us the user walked out on it.
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main,
        ) { [weak self] _ in self?.appMovedToBackground() }
        skipHandler = onAdSkipped
        // Watching it through is what keeps the connection, so the outcome of
        // this one showing has to be tracked, not just that it opened.
        ProfileStore.shared.appendTunnelLine("[ads] showing")
        ad.present(fromRootViewController: root) { [weak self] in
            self?.earnedReward = true
            ProfileStore.shared.appendTunnelLine("[ads] reward earned")
        }
    }
}

extension AdsManager {
    private func stopWatchingBackground() {
        if let observer = backgroundObserver { NotificationCenter.default.removeObserver(observer) }
        backgroundObserver = nil
    }

    /// Leaving the app with the ad still up is how the free connection was had
    /// for nothing on iOS: nothing else notices, since the ad never dismisses.
    func appMovedToBackground() {
        guard isAdOnScreen, !earnedReward, !didClickAd, let handler = skipHandler else { return }
        skipHandler = nil
        stopWatchingBackground()
        ProfileStore.shared.appendTunnelLine("[ads] app left with the ad unfinished; the tunnel goes down")
        handler()
    }
}

extension AdsManager: GADFullScreenContentDelegate {
    func adDidRecordClick(_ ad: GADFullScreenPresentingAd) {
        didClickAd = true
    }

    func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        isAdOnScreen = false
        stopWatchingBackground()
        rewardedInterstitial = nil
        // The reward can arrive just after the dismissal rather than before it,
        // and judging an ad skipped in that gap would drop a tunnel the user
        // had in fact paid for with their attention. The next ad is fetched only
        // for a connection that goes on, while it still carries the request.
        let handler = skipHandler
        skipHandler = nil
        ProfileStore.shared.appendTunnelLine("[ads] dismissed, reward=\(earnedReward)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            if self.earnedReward {
                self.loadAd()
                return
            }
            ProfileStore.shared.appendTunnelLine("[ads] no reward after the grace period; the tunnel goes down")
            handler?()
        }
    }
    func ad(_ ad: GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        isAdOnScreen = false
        stopWatchingBackground()
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
