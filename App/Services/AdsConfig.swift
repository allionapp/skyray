import Foundation

/// Google AdMob identifiers for SkyRay (app `com.allion.skyray`, iOS).
/// The application identifier also has to be set in `project.yml` under
/// `GADApplicationIdentifier` (Info.plist can't read Swift constants), so if
/// you ever rotate these, update both places.
enum AdsConfig {
    /// AdMob application ID, iOS app "SkyRay".
    static let appID = "ca-app-pub-8085563084618250~4284064162"
    /// Rewarded-interstitial ad unit shown once after a fresh connect.
    static let rewardedInterstitialUnitID = "ca-app-pub-8085563084618250/6268546323"
}
