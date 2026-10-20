import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    TextRecognizer.register(with: engineBridge.applicationRegistrar.messenger())
    AccessibilitySettings.register(with: engineBridge.applicationRegistrar.messenger())
  }
}

/// Tells the app whether Reduce Transparency is on, which Flutter does not report, and when it changes.
final class AccessibilitySettings {
  static let channelName = "ucsc_router/accessibility"
  private static var shared: AccessibilitySettings?

  private let channel: FlutterMethodChannel
  private var observer: NSObjectProtocol?

  private init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: AccessibilitySettings.channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "reduceTransparency" else { return result(FlutterMethodNotImplemented) }
      result(UIAccessibility.isReduceTransparencyEnabled)
    }
    observer = NotificationCenter.default.addObserver(
      forName: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      self?.channel.invokeMethod("reduceTransparencyChanged", arguments: UIAccessibility.isReduceTransparencyEnabled)
    }
  }

  static func register(with messenger: FlutterBinaryMessenger) {
    shared = AccessibilitySettings(messenger: messenger)
  }
}
