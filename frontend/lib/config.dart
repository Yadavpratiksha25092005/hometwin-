// Backend (Go) address.
//
//  * Empty ('')  = DEMO mode: no server, all data is stored on the phone.
//  * Server mode = put the computer's IP in defaultValue below (currently: 192.168.1.14).
//      - Real phone (same Wi-Fi):  http://192.168.1.14:8080
//      - Android emulator:         http://10.0.2.2:8080
//      - USB phone + `adb reverse tcp:8080 tcp:8080`:  http://localhost:8080
const String kApiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://192.168.1.17:8080');

// true = "3D scan from video" is a DEMO for now (sample 3D rooms are added).
// Set this to false once a real video -> 3D pipeline is connected.
const bool kMockVideoScan = false;