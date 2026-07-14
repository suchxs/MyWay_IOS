# MyWay for iOS — Setup

SwiftUI port of the Android app. Same Firebase backend, same Firestore data — an iOS user and an
Android user share friends, groups, chats and pins with no migration.

## 0. Prerequisites
- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- Access to the existing Firebase project **`myway-b2954`** and its Google Cloud project.

## 1. Generate the Xcode project
```bash
cd IOS/MyWay_IOS
xcodegen generate          # reads project.yml → MyWay.xcodeproj
open MyWay.xcodeproj
```
Xcode resolves the Swift Package dependencies (Firebase, GoogleSignIn, GoogleMaps) on first open.

## 2. Firebase — add an iOS app to the SAME project (do NOT make a new one)

The Firebase project and the Google Cloud project are shared across platforms. `com.usc.myway` today
only has an **Android** app registered; you add an **iOS** app beside it.

1. [Firebase Console](https://console.firebase.google.com) → project **myway-b2954** → ⚙️ **Project settings** → **Your apps** → **Add app → iOS**.
2. **Apple bundle ID:** `com.usc.myway` (matches `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml`).
3. Download **`GoogleService-Info.plist`** and drag it into the Xcode project, into the `MyWay/` group,
   **with "Copy items if needed" checked** and the MyWay target ticked. (It's gitignored — never commit it.)
4. Auth providers are configured per-project, so **Email/Password** and **GitHub** already work.
   For **Google Sign-In**, adding the iOS app auto-creates an iOS OAuth client — no extra console step.

### Google Sign-In URL scheme
Open the new `GoogleService-Info.plist`, copy the **`REVERSED_CLIENT_ID`** value, and paste it into
`project.yml` in place of `REPLACE_WITH_REVERSED_CLIENT_ID`, then re-run `xcodegen generate`.
(Or set it directly in Xcode → target → Info → URL Types.)

## 3. Google Maps — the iOS app needs its OWN API key

The current `MAPS_API_KEY` is restricted to the Android app's package name + SHA-1, so it will **not**
work on iOS. Create a sibling key in the **same Google Cloud project**:

1. [Google Cloud Console](https://console.cloud.google.com) → same project as `myway-b2954` →
   **APIs & Services → Enable APIs** → enable **Maps SDK for iOS** (and **Places API** if you wire up search).
2. **Credentials → Create credentials → API key.**
3. **Restrict** it: Application restrictions → **iOS apps** → add bundle ID `com.usc.myway`.
   API restrictions → **Maps SDK for iOS** (+ Places SDK for iOS if used).
4. Put the key in the app. It's read from Info.plist key **`GMSApiKey`** (see `MapsConfig` in `MyWayApp.swift`).
   In Xcode → target → Info, add a row: `GMSApiKey` = *your key*. Keep it out of git (use an xcconfig or
   Info.plist that's gitignored if you prefer).

## 4. Push notifications (FCM)
1. Apple Developer → create an **APNs Auth Key** (.p8).
2. Firebase Console → Project settings → **Cloud Messaging** → **APNs Authentication Key** → upload it.
3. In Xcode, enable the **Push Notifications** and **Background Modes → Remote notifications** capabilities
   (Background Modes is already declared in `project.yml`).
4. **Cloud Function note:** `functions/index.js` currently sends **data-only** messages with an
   `android:` block. iOS won't wake for data-only pushes when killed — add an `apns` + `notification`
   payload to `pushData()` so iOS devices get alerted too. One-line-ish change; see the TODO in
   `functions/index.js` when you get to it.

## 5. Firestore rules
No change needed — the rules in `../../firestore.rules` are platform-agnostic and already cover every
collection this app touches.

## 6. Run
Pick a simulator or device and ⌘R.

---

## What's ported vs. deferred

**Fully ported** (parity with Android): auth (email/Google/GitHub, verify-email, password reset),
onboarding + @tag claim, the map home (Google Map, saved pins, drop/save, current-location card + GPS
stats, side drawer), place detail (rename/note/collection/share-to-group/delete), Friends (search,
requests, close friends), Groups (create, list, chat with text/image/shared-pin, read receipts,
roster/roles/leave), Profile (name/tag/avatar/delete data), Settings (dark mode, pin colour, wipe data),
Collections, and the full Firestore service layer (`Services/`), which mirrors the Kotlin objects 1:1.

**Trip Mode + live location tracking** (`Trip.swift`, `LiveShare.swift`, `TripManager.swift`,
`TripRosterView.swift`): start/join/leave/end a group trip; live members, shared trip pins, and the
shared destination render on the map; a live-trip bar + roster; the shared Plan queue (service layer).
Android's foreground `TripLocationService` is replaced by a background `CLLocationManager` publisher
(`UIBackgroundModes: location`) driven by the same "publish exactly while `trip_participants/{uid}`
exists" rule — writing `trip_participants/{uid}` and `live_shares/{uid}` with an 8s throttle + 20s
heartbeat. **Background location needs a real device or a simulator with a simulated location** (Xcode →
Debug → Simulate Location), and iOS shows a permission prompt for "Always" access on first trip.

**Still deferred** (not in the current scope):
- **Turn-by-turn directions / navigation** — Routes API client + polyline + voice (`Directions.kt`,
  `DirectionsUi.kt`). Trip Mode shows the destination as a marker but not a routed line yet.
- **Private 1-on-1 DMs** (`PrivateChatActivity`) — Messages currently routes to Groups.
- **Google Places autocomplete search** — the search bar is a placeholder; drop in `GMSAutocompleteViewController`.
- **In-app heads-up notifications** (`NotificationHub`) — foreground FCM handling is stubbed in `AppDelegate`.
- **Collection-offer + full Plan UI** — the service methods exist (`Trip.addPlanItem` etc.); the editor UI is minimal.

## Account-linking note
Android's login links a colliding provider (e.g. sign in with Google when the email already has a
password account). The iOS `LoginView` signs in but doesn't yet run that link dance — add it in
`AuthService` with `user.link(with:)` if you need cross-provider linking on iOS.
