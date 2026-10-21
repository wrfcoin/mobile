import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var blurView: UIVisualEffectView?
  private var screenSecurityEnabled = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "com.wrfcoin.wrfcoin_mobile/screen_security",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] (call, result) in
        switch call.method {
        case "enableScreenSecurity":
          self?.screenSecurityEnabled = true
          result(nil)
        case "disableScreenSecurity":
          self?.screenSecurityEnabled = false
          self?.removeBlurOverlay()
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(appWillResignActive),
      name: UIApplication.willResignActiveNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(appDidBecomeActive),
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )

    return result
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  @objc private func appWillResignActive() {
    guard screenSecurityEnabled else { return }
    addBlurOverlay()
  }

  @objc private func appDidBecomeActive() {
    removeBlurOverlay()
  }

  private func addBlurOverlay() {
    guard blurView == nil, let window = self.window else { return }
    let blur = UIBlurEffect(style: .light)
    let view = UIVisualEffectView(effect: blur)
    view.frame = window.bounds
    view.tag = 999
    window.addSubview(view)
    blurView = view
  }

  private func removeBlurOverlay() {
    blurView?.removeFromSuperview()
    blurView = nil
  }
}
