# MyWay for iOS 🗺️

SwiftUI port of the [MyWay](../../README.md) Android app. Same Firebase backend, same Firestore schema —
iOS and Android users share friends, groups, chats and pins with zero migration.

- **Stack:** SwiftUI (iOS 16+), Firebase (Auth / Firestore / Messaging), Google Maps SDK for iOS,
  Google Sign-In. No Storyboards.
- **Project generation:** [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `project.yml` is the source
  of truth; `MyWay.xcodeproj` is generated and gitignored.

## Quick start
```bash
brew install xcodegen
cd IOS/MyWay_IOS
xcodegen generate
open MyWay.xcodeproj
```
Then follow **[SETUP.md](SETUP.md)** to add `GoogleService-Info.plist`, the Maps SDK key, and the
Google Sign-In URL scheme. **The app will not build until those three are in place.**

## Layout
```
MyWay/
├── MyWayApp.swift        # @main, Firebase + Maps init, push registration (App.kt)
├── RootView.swift        # auth routing: login → onboarding → map
├── AppState.swift        # live places/collections mirror + device settings (App.kt)
├── Models.swift          # data models (Collection/Places/Friends/Groups .kt data classes)
├── Theme.swift           # teal brand colours (Theme.kt)
├── Services/             # Firestore layer — 1:1 with the Kotlin objects
│   ├── Profiles.swift  Places.swift  Friends.swift  Groups.swift  FcmTokens.swift
├── Auth/                 # LoginView, RegisterView, OnboardingView, AuthService, AuthComponents
├── Map/                  # MapHomeView, GoogleMapView, LocationManager, Sidebar, PlaceSheet, MapStyle
├── Social/               # FriendsView, GroupsView, GroupChatView, ProfileView
├── Collections/          # CollectionsView
├── Settings/             # SettingsView
└── Common/               # Avatar (base64 image ↔ UIImage, same wire format as Android)
```

See **[SETUP.md](SETUP.md)** for the full Firebase/Maps/push checklist and the ported-vs-deferred list.
