# Installing on an iPhone

The app runs on iOS 15 or later with the same features as Android: Bluetooth to the harness,
the live skeleton, Buko, assessments and CSV export. Apple only lets apps onto an iPhone if they
are built on a Mac and signed with an Apple ID, so pick one of the three routes below.

## Route A: you have a Mac (simplest)

1. Install Xcode from the App Store, then Flutter (`docs/SETUP.md`) and CocoaPods
   (`brew install cocoapods`).
2. Open `app/ios/Runner.xcworkspace` in Xcode → Runner → Signing & Capabilities → Team: add your
   Apple ID (a free one works). If Xcode says the bundle ID is taken, change it to something
   unique, e.g. `edu.thesis.posturetriage.<yourname>`.
3. Plug in the iPhone, trust the computer, and turn on Settings → Privacy & Security →
   Developer Mode (the phone restarts).
4. `cd app && flutter run --release` and choose the iPhone.
5. First launch: Settings → General → VPN & Device Management → trust your Apple ID.

With a free Apple ID the app stops opening after 7 days; run step 4 again to renew it.

## Route B: no Mac (GitHub builds it, you sign it on Windows)

1. Push this repository to GitHub. Open the Actions tab → "Build iOS app" → Run workflow
   (`.github/workflows/ios.yml`). It builds on a GitHub-hosted Mac in about 10 minutes.
2. Download `PostureTriage-unsigned-ipa` from the finished run and unzip it to get
   `PostureTriage-unsigned.ipa`.
3. On a Windows PC or Mac, install Sideloadly (or AltStore), connect the iPhone by cable, drop in
   the .ipa and sign in with an Apple ID. It signs and installs the app.
4. On the iPhone: turn on Developer Mode and trust the Apple ID as in Route A, steps 3 and 5.

Same 7-day limit with a free Apple ID; re-sign with Sideloadly to renew.

## Route C: several iPhones, no 7-day limit (TestFlight)

Needs a paid Apple Developer Program membership. In Xcode: Product → Archive → Distribute App →
App Store Connect, then add the panel's or participants' emails as TestFlight testers. They
install the TestFlight app and accept the invite. Builds last 90 days.

## What is already set up in `app/ios`

- Bundle ID `edu.thesis.posturetriage.postureTriage`, display name "Posture Triage", iOS 15.0.
- `NSBluetoothAlwaysUsageDescription` in `Runner/Info.plist` (iOS asks for Bluetooth on first
  connect; without this text the app would crash).
- Exported CSVs open the iOS share sheet (anchored for iPad); saved sessions are also visible in
  the Files app under "On My iPhone → Posture Triage".
- 3D scenes use WKWebView, which supports WebGL on every iPhone that runs iOS 15.

## Not an option: the browser build

Safari on iPhone has no Web Bluetooth, so the web build can only run the demo there, never the
real harness.
