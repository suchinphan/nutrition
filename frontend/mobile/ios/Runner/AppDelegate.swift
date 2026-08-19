import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    // flutter_local_notifications iOS setup: ต้องตั้ง delegate นี้ก่อน
    // super.application(...) ไม่งั้น local notification ไม่โผล่ตอนแอปเปิดอยู่
    // (foreground) — ดู UNUserNotificationCenter setup guide ของ package
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
