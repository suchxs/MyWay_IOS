// App entry — mirrors App.kt: Firebase init, Google Maps key, push registration, and the
// in-memory data mirror (AppState) kept live by Firestore snapshot listeners.
import SwiftUI
import FirebaseCore
import FirebaseAuth
import FirebaseMessaging
import GoogleMaps
import GooglePlaces
import GoogleSignIn
import UserNotifications

@main
struct MyWayApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .preferredColorScheme(state.darkMode ? .dark : .light)
                .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, MessagingDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()
        // Maps key comes from GoogleService-Info.plist's API_KEY is NOT used; Maps needs its own key.
        GMSServices.provideAPIKey(MapsConfig.apiKey)
        GMSPlacesClient.provideAPIKey(MapsConfig.apiKey)   // landmark details / autocomplete
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self

        // Already signed in on relaunch → bind listeners + register push (App.kt onCreate tail).
        if let uid = Auth.auth().currentUser?.uid {
            AppState.shared.bindUser(uid)
            FcmTokens.register(uid)
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    // New FCM token → store under the signed-in user (MyFirebaseMessagingService.onNewToken equivalent).
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        if let uid = Auth.auth().currentUser?.uid, let t = fcmToken { FcmTokens.save(uid, token: t) }
    }

    // Foreground push: the in-app NotificationHub already handles alerts, so suppress the banner (matches
    // Android's inForeground check), but still let it through if you prefer — keep it simple for now.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

// Google Maps needs its own key (Android read ${MAPS_API_KEY} from the manifest). See SETUP.md.
enum MapsConfig {
    // ponytail: read from Info.plist so the key isn't hard-coded in source.
    static let apiKey: String = (Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String) ?? ""
    // Routes API (REST) needs a key without an iOS-app restriction; falls back to the Maps key.
    static let routesKey: String = {
        let k = (Bundle.main.object(forInfoDictionaryKey: "RoutesApiKey") as? String) ?? ""
        return k.isEmpty ? apiKey : k
    }()
}
