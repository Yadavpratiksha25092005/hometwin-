# Home Digital Twin – Flutter App

## Setup
1. Install Flutter SDK (3.19+).
2. In this folder run (generates android/ios folders):
       flutter create . --project-name home_digital_twin --org com.hometwin
   (keeps lib/ and pubspec.yaml as they are)
3. `flutter pub get`
4. Set backend URL in `lib/api.dart` (`baseUrl`):
   - Android emulator: http://10.0.2.2:8080
   - iOS simulator: http://localhost:8080
   - Real phone: http://<your-pc-ip>:8080
5. Android: allow http in `android/app/src/main/AndroidManifest.xml` -> add
   `android:usesCleartextTraffic="true"` inside <application> (dev only).
6. `flutter run`

## Features in this MVP
Login/Signup (JWT), Assets, Warranties + expiry reminders, Document Vault (upload),
Repair History, 3D scan records (upload .glb/.usdz), Export/Share home report.

## Next steps (3D scan + AR)
- 3D scan: Android -> ARCore Depth / Polycam export; iOS -> RoomPlan (LiDAR) via platform channel.
  Upload exported model with the existing upload flow.
- 3D viewer / AR preview: add `model_viewer_plus` (view .glb, AR on tap).
- Push notifications: add `firebase_messaging`, send token to POST /api/device-token.
