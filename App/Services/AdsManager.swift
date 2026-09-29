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
    /// The tunnel whose request is in flight, if any. A request of an earlier tunnel does not
    /// hold back the current one's.
    private var loadingGeneration: Int?
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
            // Anything of Google's still on screen would go on over the real network: close it.
            // An ad closed this way is no walk-out (the tunnel is gone already): no skip handler.
            if isAdOnScreen {
                skipHandler = nil
                ProfileStore.shared.appendTunnelLine("[ads] tunnel down with the ad on screen; closing it")
            }
            if isAdOnScreen || consentFormShowing {
                presentingRoot?.presentedViewController?.dismiss(animated: false)
            }
            // A consent chain cut off here never gets UMP's completion (a form closed in code is
            // no choice): end it now, and ignore anything it still reports. The next Connect asks
            // again over its own tunnel.
            if setup == .consenting {
                consentChain += 1
                consentFormShowing = false
                setup = .idle
            }
            rewardedInterstitial = nil
            loadedAt = nil
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
        consentChain += 1
        let chain = consentChain
        ProfileStore.shared.appendTunnelLine("[ads] consent check")
        let parameters = UMPRequestParameters()
        parameters.tagForUnderAgeOfConsent = false
        UMPConsentInformation.sharedInstance.requestConsentInfoUpdate(with: parameters) { [weak self] error in
            Task { @MainActor in
                guard let self, chain == self.consentChain else { return }
                // The tunnel went down meanwhile: nothing more of Google's until the next connect.
                guard self.tunnelUp else { self.setup = .idle; return }
                if let error {
                    // Consent could not be looked up (e.g. no consent message set up for the app
                    // in AdMob): whether ads may be requested is unknown, and the request goes on
                    // as before; the log says so.
                    self.consentUnknown = true
                    ProfileStore.shared.appendTunnelLine("[ads] consent info failed: \(error.localizedDescription)")
                }
                guard error == nil, let root = UIApplication.topMostViewController() else {
                    self.requestTrackingThenInitialize(chain: chain)
                    return
                }
                self.consentFormShowing = true
                self.presentingRoot = root
                UMPConsentForm.loadAndPresentIfRequired(from: root) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, chain == self.consentChain else { return }
                        self.consentFormShowing = false
                        guard self.tunnelUp else { self.setup = .idle; return }
                        self.requestTrackingThenInitialize(chain: chain)
                    }
                }
            }
        }
    }

    private func requestTrackingThenInitialize(chain: Int) {
        ATTrackingManager.requestTrackingAuthorization { [weak self] _ in
            Task { @MainActor in
                guard let self, chain == self.consentChain else { return }
                self.initializeAndLoad()
            }
        }
    }

    /// Whether the consent lookup failed this run (then the answer is unknown, not "no").
    private var consentUnknown = false
    private var consentFormShowing = false
    /// Counts consent chains; a callback from one that was cut off is ignored.
    private var consentChain = 0
    /// The view controller the consent form or the ad was presented from, to close it if the
    /// tunnel goes down while it is up.
    private weak var presentingRoot: UIViewController?

    private func initializeAndLoad() {
        // The tunnel went down during the prompts: the SDK starts with the next connect.
        guard tunnelUp else {
            setup = .idle
            return
        }
        // Consent was looked up and does not allow ad requests (the user said no, or the form
        // could not be shown): no request, and consent is asked again with the next connect.
        if !consentUnknown, !UMPConsentInformation.sharedInstance.canRequestAds {
            ProfileStore.shared.appendTunnelLine("[ads] no consent to request ads; none this time")
            setup = .idle
            giveUpPending()
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
        guard tunnelUp, setup == .ready, loadingGeneration != tunnelGeneration, rewardedInterstitial == nil else { return }
        let generation = tunnelGeneration
        loadingGeneration = generation
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
        if loadingGeneration == generation { loadingGeneration = nil }
        // An ad that arrives after its tunnel went down was fetched over that tunnel; kept for
        // the next connect only if one is up now, else dropped (it was closed with the tunnel).
        if ad != nil, generation != tunnelGeneration, !tunnelUp { return }
        if let ad {
            ProfileStore.shared.appendTunnelLine("[ads] loaded")
            rewardedInterstitial = ad
            loadedAt = Date()
            ad.fullScreenContentDelegate = self
            showPending()
            return
        }
        ProfileStore.shared.appendTunnelLine("[ads] no ad: \(error?.localizedDescription ?? "unknown")")
        // A request from an earlier tunnel: the connect waiting now has (or gets) its own.
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
        switch UIApplication.shared.applicationState {
        case .background:
            // The user left: no ad pops up on their return.
            giveUpPending()
            return
        case .inactive:
            waitForActive()   // a system prompt (tracking, consent) is up
            return
        default:
            break
        }
        guard let root = UIApplication.topMostViewController() else {
            giveUpPending()
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
        backgroundWhileWaiting = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main,
        ) { [weak self] _ in Task { @MainActor in self?.giveUpPending() } }
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
        if let observer = backgroundWhileWaiting { NotificationCenter.default.removeObserver(observer) }
        activeObserver = nil
        backgroundWhileWaiting = nil
    }
    private var backgroundWhileWaiting: NSObjectProtocol?

    /// The connecting screen closed for its own reason (cap, failed start, cancel): the ad it
    /// was waiting for must not pop up over Home later.
    func cancelPending() {
        giveUpPending()
    }

    /// Whether Google asks for a way to change consent later (Settings shows "Privacy choices").
    /// Known after the first consent lookup of the run; false before it.
    var privacyChoicesRequired: Bool {
        UMPConsentInformation.sharedInstance.privacyOptionsRequirementStatus == .required
    }

    /// Settings' "Privacy choices": Google's form to change consent. Over the tunnel only, like
    /// everything of Google's; reports false when it could not be shown (not connected).
    func showPrivacyChoices(from root: UIViewController, done: @escaping (Bool) -> Void) {
        guard tunnelUp else { return done(false) }
        presentingRoot = root
        consentFormShowing = true
        UMPConsentForm.presentPrivacyOptionsForm(from: root) { [weak self] error in
            Task { @MainActor in
                self?.consentFormShowing = false
                if let error { ProfileStore.shared.appendTunnelLine("[ads] privacy choices failed: \(error.localizedDescription)") }
                done(error == nil)
            }
        }
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
        presentingRoot = root
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
