import UIKit
import Flutter
import GoogleMaps

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    // Prefer Info.plist → GMSServicesApiKey
    if let apiKey = Bundle.main.object(forInfoDictionaryKey: "GMSServicesApiKey") as? String,
       !apiKey.isEmpty {
      GMSServices.provideAPIKey(apiKey)
    } else {
      // Fallback: set a literal if you really want to hard-code it
      // Replace with your real key or remove this block.
      let MAP_API_KEY = "YOUR_IOS_MAPS_API_KEY"
      GMSServices.provideAPIKey(MAP_API_KEY)
      print("⚠️ GMSServicesApiKey not found in Info.plist; used hardcoded MAP_API_KEY.")
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
