import Foundation

/// Google AdMob identifiers for SkyRay (app `com.allion.skyray`, iOS).
/// The application identifier also has to be set in `project.yml` under
/// `GADApplicationIdentifier` (Info.plist can't read Swift constants), so if
/// you ever rotate these, update both places.
enum AdsConfig {
    /// AdMob application ID, iOS app "SkyRay".
    static let appID = "ca-app-pub-8085563084618250~4284064162"
    /// Rewarded-interstitial ad unit shown once after a fresh connect.
    #if DEBUG
    /// Google's own demo unit: a development build on a real phone only ever gets test ads.
    static let rewardedInterstitialUnitID = "ca-app-pub-3940256099942544/6978759866"
    #else
    static let rewardedInterstitialUnitID = "ca-app-pub-8085563084618250/6268546323"
    #endif
}
