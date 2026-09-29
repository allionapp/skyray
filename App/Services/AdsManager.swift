import AppTrackingTransparency
import GoogleMobileAds
import UIKit
import UserMessagingPlatform

/// Loads a Google AdMob rewarded-interstitial ad and shows it once after each
/// fresh connect (not on every reconnect/network blip). Not used inside the
/// tunnel extension — this only runs in the main app.
///
/// Order, all of it over the tunnel (VPNManager sets `tunnelUp` first): Google's
/// UMP consent (GDPR/UK), then Apple's tracking prompt, then the SDK's start, and
/// only then the ad request. Nothing of Google's runs while the tunnel is down.
/// Every outcome — loaded, no ad and why, shown, reward — goes to the app log, so a
/// build that shows no ad can say why.
@MainActor
final class AdsManager: NSObject, ObservableObject {
    static let shared = AdsManager()

    private enum Setup { case idle, consenting, ready }
    private var setup = Setup.idle

    private var rewardedInterstitial: GADRewardedInterstitialAd?
    /// When the cached ad arrived: Google's ads expire after an hour, so an older one is
    /// replaced rather than shown (it would fail to present).
    private var loadedAt: Date?
    private let maxAdAge: TimeInterval = 55 * 60
    private var isLoadingAd = false
    /// Counts tunnels: a request that belongs to an earlier one must not decide the current
    /// connect's ad.
    private var tunnelGeneration = 0
    private var requestedBefore = false
    private var lastShown: Date?
    /// Cooldown so a flaky connection that drops and reconnects repeatedly
    /// doesn't show an ad every time. Counted from an ad actually on screen.
    private let minInterval: TimeInterval = 20 * 60
    /// How long the connecting screen waits for the ad once it has been requested; longer the
    /// first time in a run, when the SDK itself is still warming up.
    private let loadWait: TimeInterval = 12
    private let firstLoadWait: TimeInterval = 25
    /// The longest it waits at all, the consent form and the tracking prompt included.
    private let maxWait: TimeInterval = 60

    /// Set by VPNManager: whether the tunnel is up and so carries this app's requests. No ad
    /// request leaves without it, so none goes to Google from the real network.
    var tunnelUp = false {
        didSet {
            guard !tunnelUp, oldValue else { return }
            tunnelGeneration += 1
            stopWaitingForActive()
            giveUpPending()
        }
    }

    /// A connect still waiting for its ad: shown when it arrives, until `pendingShowUntil`.
    private var pendingShowUntil: Date?
    private var pendingSkipHandler: (() -> Void)?
    private var pendingReady: (() -> Void)?
    private var pendingRetried = false
    private var activeObserver: NSObjectProtocol?

    private override init() { super.init() }

    /// On each fresh connect, over the tunnel: consent, tracking prompt, SDK start. Once done,
    /// it stays done for the life of the process.
    func start() {
        guard tunnelUp, setup == .idle else { return }
        setup = .consenting
        ProfileStore.shared.appendTunnelLine("[ads] consent check")
        let parameters = UMPRequestParameters()
        parameters.tagForUnderAgeOfConsent = false
        UMPConsentInformation.sharedInstance.requestConsentInfoUpdate(with: parameters) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if let error { ProfileStore.shared.appendTunnelLine("[ads] consent info failed: \(error.localizedDescription)") }
                guard error == nil, let root = UIApplication.topMostViewController() else {
                    self.requestTrackingThenInitialize()
                    return
                }
                UMPConsentForm.loadAndPresentIfRequired(from: root) { [weak self] _ in
                    Task { @MainActor in self?.requestTrackingThenInitialize() }
                }
            }
        }
    }

    private func requestTrackingThenInitialize() {
        ATTrackingManager.requestTrackingAuthorization { [weak self] _ in
            Task { @MainActor in self?.initializeAndLoad() }
        }
    }

    private func initializeAndLoad() {
        // The tunnel went down during the prompts: the SDK starts with the next connect.
        guard tunnelUp else {
            setup = .idle
            return
        }
        #if DEBUG
        GADMobileAds.sharedInstance().requestConfiguration.testDeviceIdentifiers = [GADSimulatorID]
        #endif
        GADMobileAds.sharedInstance().start(completionHandler: nil)
        setup = .ready
        ProfileStore.shared.appendTunnelLine("[ads] SDK started")
        loadAd()
    }

    private func loadAd() {
        guard tunnelUp, setup == .ready, !isLoadingAd, rewardedInterstitial == nil else { return }
        isLoadingAd = true
        let generation = tunnelGeneration
        // From the request on, the connecting screen waits only so long for the answer.
        if let until = pendingShowUntil {
            pendingShowUntil = min(until, Date().addingTimeInterval(requestedBefore ? loadWait : firstLoadWait))
            watchDeadline()
        }
        requestedBefore = true
        AdSignalOverride.reassert()
        ProfileStore.shared.appendTunnelLine("[ads] request over the tunnel: \(AdSignalOverride.snapshot())")
        GADRewardedInterstitialAd.load(withAdUnitID: AdsConfig.rewardedInterstitialUnitID, request: GADRequest()) { [weak self] ad, error in
            Task { @MainActor in self?.loaded(ad, error: error, generation: generation) }
        }
    }

    private func loaded(_ ad: GADRewardedInterstitialAd?, error: Error?, generation: Int) {
        isLoadingAd = false
        if let ad {
            ProfileStore.shared.appendTunnelLine("[ads] loaded")
            rewardedInterstitial = ad
            loadedAt = Date()
            ad.fullScreenContentDelegate = self
            showPending()
            return
        }
        ProfileStore.shared.appendTunnelLine("[ads] no ad: \(error?.localizedDescription ?? "unknown")")
        // A request from an earlier tunnel: the connect waiting now gets a request of its own.
        guard generation == tunnelGeneration else {
            if pendingReady != nil { loadAd() }
            return
        }
        // One more try while the connecting screen still has time for it.
        if let until = pendingShowUntil, until.timeIntervalSinceNow > 5, !pendingRetried {
            pendingRetried = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.loadAd() }
        } else {
            giveUpPending()
        }
    }

    /// The ad a connect was waiting for has arrived: shown now if the app is in front, or as
    /// soon as it is again (the tracking or consent prompt was up), while still in time.
    private func showPending() {
        guard pendingReady != nil, let ad = rewardedInterstitial else { return }
        guard tunnelUp, let until = pendingShowUntil, Date() < until else {
            giveUpPending()
            return
        }
        guard UIApplication.shared.applicationState == .active, let root = UIApplication.topMostViewController() else {
            waitForActive()
            return
        }
        let skip = pendingSkipHandler
        let ready = pendingReady
        stopWaitingForActive()
        clearPending()
        present(ad, from: root, onAdSkipped: skip ?? {}, onReady: ready ?? {})
    }

    private func waitForActive() {
        guard activeObserver == nil else { return }
        activeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main,
        ) { [weak self] _ in
            Task { @MainActor in
                self?.stopWaitingForActive()
                self?.showPending()
            }
        }
    }

    private func stopWaitingForActive() {
        if let observer = activeObserver { NotificationCenter.default.removeObserver(observer) }
        activeObserver = nil
    }

    private func clearPending() {
        pendingShowUntil = nil
        pendingSkipHandler = nil
        pendingReady = nil
        pendingRetried = false
    }

    /// No ad for this connect after all: the connecting screen is told, and nothing shows later.
    private func giveUpPending() {
        let ready = pendingReady
        stopWaitingForActive()
        clearPending()
        ready?()
    }

    private func watchDeadline() {
        guard let until = pendingShowUntil else { return }
        let wait = max(0, until.timeIntervalSinceNow) + 0.05
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard let self, let current = self.pendingShowUntil else { return }
            if Date() >= current {
                ProfileStore.shared.appendTunnelLine("[ads] no ad in time; connected without one")
                self.giveUpPending()
            } else {
                self.watchDeadline()
            }
        }
    }

    /// Set while an ad is on screen: whether it ran to the end, and who to tell if it didn't.
    private var earnedReward = false
    private var skipHandler: (() -> Void)?
    private var presentReady: (() -> Void)?
    private var isAdOnScreen = false
    private var backgroundObserver: NSObjectProtocol?
    /// A tap on the ad sends the user to the App Store, which also backgrounds
    /// the app; that is the advertiser's own call to action, not a walk-out.
    private var didClickAd = false

    /// Right after a fresh connect. [onReady] runs exactly once: when the ad goes on screen, or
    /// when it is clear none will (cooldown, no fill, the wait limits passed, the tunnel went
    /// down). The connecting screen closes then. [onAdSkipped] runs when the ad was shown but
    /// closed before the reward.
    func showAfterConnect(onAdSkipped: @escaping () -> Void, onReady: @escaping () -> Void) {
        var done = false
        let ready = { if !done { done = true; onReady() } }
        guard tunnelUp else { return ready() }
        if let last = lastShown, Date().timeIntervalSince(last) < minInterval {
            ProfileStore.shared.appendTunnelLine("[ads] none this time: the last one was \(Int(Date().timeIntervalSince(last) / 60)) min ago")
            return ready()
        }
        giveUpPending()
        pendingShowUntil = Date().addingTimeInterval(maxWait)
        pendingSkipHandler = onAdSkipped
        pendingReady = ready
        watchDeadline()
        if let at = loadedAt, rewardedInterstitial != nil, Date().timeIntervalSince(at) > maxAdAge {
            ProfileStore.shared.appendTunnelLine("[ads] the cached ad is too old; a new one")
            rewardedInterstitial = nil
            loadedAt = nil
        }
        if rewardedInterstitial != nil {
            showPending()
        } else {
            // Before the SDK's start, the request waits for it (start() is under way).
            loadAd()
        }
    }

    private func present(_ ad: GADRewardedInterstitialAd, from root: UIViewController,
                         onAdSkipped: @escaping () -> Void, onReady: @escaping () -> Void) {
        earnedReward = false
        didClickAd = false
        isAdOnScreen = true
        skipHandler = onAdSkipped
        presentReady = onReady
        // SwiftUI's scenePhase does not reach a view the ad has covered, so the
        // notification is what tells us the user walked out on it.
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main,
        ) { [weak self] _ in Task { @MainActor in self?.appMovedToBackground() } }
        // Watching it through is what keeps the connection, so the outcome of
        // this one showing has to be tracked, not just that it opened.
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

    func adWillPresentFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        // The cooldown counts from an ad really on screen, not from an attempt.
        lastShown = Date()
        ProfileStore.shared.appendTunnelLine("[ads] showing")
        let ready = presentReady
        presentReady = nil
        ready?()
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
        ProfileStore.shared.appendTunnelLine("[ads] could not show: \(error.localizedDescription)")
        isAdOnScreen = false
        stopWatchingBackground()
        rewardedInterstitial = nil
        skipHandler = nil
        let ready = presentReady
        presentReady = nil
        ready?()
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
