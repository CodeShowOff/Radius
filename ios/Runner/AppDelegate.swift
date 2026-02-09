import Flutter
import UIKit
import Firebase
import FirebaseMessaging
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Configure Firebase
    FirebaseApp.configure()

    // Configure Google Maps for Nearby Help feature
    // API key is stored securely in Keys.xcconfig (not committed to git)
    if let mapsApiKey = Bundle.main.object(forInfoDictionaryKey: "MAPS_API_KEY_IOS") as? String {
      GMSServices.provideAPIKey(mapsApiKey)
    }

    // Configure notifications
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }
    
    // Register for remote notifications
    application.registerForRemoteNotifications()
    
    GeneratedPluginRegistrant.register(with: self)
    
    // Register BLE Advertiser Plugin
    let controller = window?.rootViewController as! FlutterViewController
    BleAdvertiserPlugin.register(with: registrar(forPlugin: "BleAdvertiserPlugin")!)
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  override func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    Messaging.messaging().apnsToken = deviceToken
  }
}
