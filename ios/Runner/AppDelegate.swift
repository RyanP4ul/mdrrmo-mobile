import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let apiKey = Self.googleMapsApiKey(), !apiKey.isEmpty {
      GMSServices.provideAPIKey(apiKey)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private static func googleMapsApiKey() -> String? {
    if let envPath = Bundle.main.path(forResource: ".env", ofType: nil, inDirectory: "flutter_assets"),
       let content = try? String(contentsOfFile: envPath, encoding: .utf8) {
      for rawLine in content.components(separatedBy: .newlines) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty || line.hasPrefix("#") { continue }
        let parts = line.split(separator: "=", maxSplits: 1)
        if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == "GOOGLE_MAP_API_KEY" {
          let value = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
          if !value.isEmpty { return value }
        }
      }
    }
    if let plistKey = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_MAP_API_KEY") as? String,
       !plistKey.isEmpty {
      return plistKey
    }
    return nil
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
