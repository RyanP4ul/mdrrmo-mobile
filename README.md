# mdrrmo_flutter

A new Flutter project.

## Android road navigation map

Set `GOOGLE_MAP_API_KEY` in the Flutter project's `.env`. Gradle injects it into
the Android manifest when building the app. After changing this key, stop the app
and run `flutter run` again; hot reload and hot restart do not update native configuration.

In the key's Google Cloud project, enable **Maps SDK for Android** and billing.
For an Android-restricted key, register package `com.example.mdrrmo_flutter` and
the SHA-1 of the certificate signing the installed build. Run
`cd android` then `.\gradlew.bat signingReport` on Windows to find the fingerprint.
See [Google's Android Maps setup guide](https://developers.google.com/maps/documentation/android-sdk/get-api-key).

Map tiles and route calculation use separate services. Set
`GOOGLE_DIRECTIONS_API_KEY=` explicitly to use OSRM routes and Photon address search
while keeping the native Google map. Without that setting, the route service falls
back to `GOOGLE_MAP_API_KEY` for Google Directions and Geocoding requests, which
need their own API enablement and compatible key restrictions.

If the map stays blank, open road navigation and capture the Maps-specific error:

```powershell
adb logcat -d -s "Google Maps Android API" "Google Maps SDK for Android"
```

Check for `Authorization failure` and follow the package / SHA-1 details in that log.
`GoogleApiManager`, `Phenotype.API`, and `FlagStore` warnings alone do not establish
that Maps authentication failed. If there is no Maps authorization error, check the
device's network connection and Google Play services, and compare with another
Play-enabled device or emulator.

## Three-way voice calls

Residents, dispatchers, and assigned responders can join a shared Agora voice call. Tap the phone icon in the app header to see invitations. Dispatchers start calls from **Reports and dispatch → Report details → Three-way voice call** after assigning a responder.

Allow microphone access and keep the call screen open. Use mute, speaker, and leave controls during the call. Rebuild/restart the app to install native calling support. Credentials stay on the Laravel server; the app uses its existing signed-in session.

See the [complete setup and usage guide](../mdrrmo/docs/agora-calls.md) for supported platforms, HTTPS requirements for web clients, and call lifecycle behavior.

## Getting Started

On first launch, choose **Resident** or **Driver / Responder**, then continue to sign in. Residents can select **Create an account** on their login screen; drivers/responders use administrator-issued accounts and have no registration option. Use **Back to role selection** (or the phone's back button) from login to switch roles. Returning users open the login for their saved role, or resume an existing supported session. Admin and dispatcher accounts use the website; legacy saved staff selections return to the mobile role chooser.

The resident workspace uses **Home**, **Reports**, **Services**, and **Updates**. Start a report from Home, follow its progress in Reports, and check service bookings under Services → My requests. Services → New request opens the booking form. Updates supports unread filtering and marking all notifications as read. Search and sign-out are in **More options**. On the incident form, **Use my current location** requests a single GPS reading and places the map pin; check that the incident address matches. Residents can also select a pin manually.

The driver/responder workspace has three tabs: **Dispatch** for the current incident, navigation, progress updates, and voice calls; **Team** for vehicle availability and contact numbers; and **History** for reviewing past responses. Pull down to refresh. Search, submitted reports, and sign-out are available in the header's **More options** menu. Account, profile editing, and password-change screens are not available in the resident or driver/responder workspace.

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
