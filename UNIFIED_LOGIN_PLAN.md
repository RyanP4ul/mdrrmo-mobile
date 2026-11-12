# Plan: Merge Resident and Driver/Responder Role Selection into Unified Login

## Goal

Remove the pre-login `RoleSelectScreen` (Resident vs. Driver / Responder) in `mdrrmo_flutter` and replace it with a single unified `LoginScreen` that:
1. Signs in both **Residents** and **Drivers / Responders** from one form based on the role returned by the backend.
2. Preserves **Create an account** (`RegisterScreen`) strictly for **Residents** while clearly explaining that **Driver / Responder** accounts are administrator-issued (no self-registration).
3. Keeps unauthenticated emergency features (**Emergency SOS** and **Continue as guest**) immediately reachable on the login screen.

---

## Why This Works Cleanly with the Existing Backend

The Laravel API (`mdrrmo/app/Http/Controllers/MobileAuthController.php`) already supports unified login:
- `POST /api/auth/mobile/login` only requires `email`, `password`, and `device_name`.
- `User::findByEmail($request->email)` resolves the user across account tables and returns `{ token, user }` with `user['role']` set to `'resident'`, `'driver/responder'`, `'admin'`, or `'dispatcher'`.
- Emails are unique across all account types (enforced by `MobileAuthController::register()` checking `Account::classes()`).
- The `expectedRole` check was **purely client-side** inside `AuthService._login()` (`mdrrmo_flutter/lib/services/auth_service.dart`). Removing it lets the server-returned `user['role']` determine whether to open `ResidentApp` or `ResponderApp`.

---

## Proposed User Flow

```text
App Launch (SplashScreen)
  ├── Valid saved token (/auth/mobile/me)
  │     ├── role == 'resident'         ──▶ ResidentApp
  │     └── role == 'driver/responder' ──▶ ResponderApp
  └── No token / expired session
        └── Unified LoginScreen
              ├── Email + Password Sign In ──▶ routes by returned user['role']
              ├── Emergency SOS (header/CTA) ─▶ SosScreen(guest: true)
              ├── Continue as guest        ──▶ GuestReportPage
              ├── New resident? Create an account ──▶ RegisterScreen (Resident-only)
              └── Helper note: "Driver & responder accounts are issued by MDRRMO."
```

---

## Implementation Steps

### 1. Simplify `AuthService` (`lib/services/auth_service.dart`)
- Remove the `String? expectedRole` parameter from `login()` and `_login()`.
- Remove the client-side mismatch check:
  ```dart
  if (expectedRole != null && user['role'] != expectedRole) { ... }
  ```
- Keep the mobile-role allowlist check (`['resident', 'driver/responder'].contains(user['role'])`) so `admin` and `dispatcher` accounts continue receiving the web-portal message.

### 2. Merge Role Context into Unified `LoginScreen` (`lib/screens/login_screen.dart`)
- Remove the required `final AccountType account` constructor argument (`const LoginScreen({super.key});`).
- Remove role-switching state and UI:
  - `_isResident`, `_changingRole`, `_changeAccountType()`, `PopScope` redirect, `AccountType.staff` post-frame callback.
  - The role `Pill` (`Resident` / `Driver / Responder`) and `"Back to role selection"` `TextButton`.
  - The `"Forgot password?"` button and navigation to `PasswordRecoveryScreen`.
  - Unused imports (`role_select_screen.dart`, `account_screen.dart`, and `app_prefs.dart` if no longer referenced).
- Also check `PasswordRecoveryScreen` in `lib/screens/account_screen.dart`: `LoginScreen` is its only caller, so remove `PasswordRecoveryScreen` (or mark/leave it only if kept for future use) to avoid dead code.
- Update `Sign In` card copy to be role-agnostic:
  - Subtitle: e.g., `"Sign in with your resident or responder account."`
- Call `AuthService().login(email: _email.text.trim(), password: _password.text)` in `_submit()` and keep the existing `switch (role)` navigation to `ResidentApp` or `ResponderApp`.
- Add / consolidate unauthenticated actions below (and in header of) `LoginScreen`:
  - **Emergency SOS** button (previously on `RoleSelectScreen`'s header) opening `SosScreen(guest: true)` so emergency calling remains 1-tap from launch.
  - **Continue as guest** button opening `GuestReportPage()`.
  - **Resident registration** CTA: `"New resident? Create an account"` opening `RegisterScreen()`.
  - **Responder account note**: concise muted caption below the sign-up link, e.g., `"Driver and responder accounts are issued by your MDRRMO administrator."` (clearly distinguishes why sign-up is resident-only without needing a separate login flow).

### 3. Remove `RoleSelectScreen` (`lib/screens/role_select_screen.dart`)
- Delete `lib/screens/role_select_screen.dart` once all callers are migrated to `LoginScreen`.

### 4. Update Launch, Session Expiry, Registration, and Logout Routing
- **`lib/screens/splash_screen.dart`**:
  - Remove `role_select_screen.dart` and `app_prefs.dart` role-branching imports.
  - Remove `AppPrefs.instance.setAccountType(...)` calls.
  - Replace `type == null ? const RoleSelectScreen() : LoginScreen(account: type)` with `destination ??= const LoginScreen();`.
- **`lib/main.dart`**:
  - Remove `role_select_screen.dart` import.
  - In `_MdrrmoAppState._sessionExpired()`, navigate directly to `const LoginScreen()` instead of checking `AppPrefs.instance.accountType`.
- **`lib/screens/register_screen.dart`**:
  - Remove `AppPrefs.instance.setAccountType(AccountType.resident)` on success.
  - Navigate to `const LoginScreen()` after closing the `"Registration submitted"` dialog.
  - Keep `"RESIDENT REGISTRATION"` / `"Create resident account"` labels so it remains unmistakably resident-only.
- **`lib/ui/logout_action.dart` and callers**:
  - Change `Future<void> logoutFrom(BuildContext context, AccountType account)` to `Future<void> logoutFrom(BuildContext context)`.
  - Remove `AppPrefs.instance.setAccountType(account)` and navigate to `const LoginScreen()`.
  - Update callers:
    - `lib/screens/resident/resident_shell.dart` (`logoutFrom(context)`)
    - `lib/screens/driver-responder/shell.dart` (`logoutFrom(context)`)
    - `lib/screens/operations_app.dart` (`logoutFrom(context)`)

### 5. Clean Up `AppPrefs` (`lib/app_prefs.dart`)
- Remove `enum AccountType`, `accountType`, and `setAccountType()` since the device no longer needs to remember a pre-login role.
- Optionally keep `AppPrefs.init()` (and remove any stale `'accountType'` key on init: `await _p.remove('accountType');`) so existing `AppStartup` initialization and future preferences remain intact without leaving dead preference data on upgraded devices.

### 6. Update and Expand Automated Tests (`test/`)
- **`test/role_selection_test.dart`** (replace or rename to `test/unified_login_test.dart`):
  - Verify first launch (`SplashScreen` -> `MdrrmoApp`) lands directly on `LoginScreen` without showing `RoleSelectScreen`.
  - Verify `LoginScreen` renders unified sign-in (without `"Forgot password?"`), Emergency SOS, `"Continue as guest"`, `"New resident? Create an account"` -> `RegisterScreen`, and the admin-issued responder notice.
  - Verify `LoginScreen` handles compact widths (`320px`) and large text scaling (`1.4x` / `2.0x`) without layout overflow.
  - Verify signing in with mock `resident` vs. `driver/responder` responses routes to the corresponding app/profile flow (or verifies `AuthService` persistence + routing).
- **`test/app_smoke_test.dart`**:
  - Remove taps on `'Resident'` and `'Continue to sign in'`; assert startup lands directly on `LoginScreen` and session expiry returns to `LoginScreen`.
- **`test/auth_service_test.dart`**:
  - Remove `expectedRole` parameters and the `'sign in rejects an account that does not match the selected role'` test.
  - Keep tests verifying `'resident'` and `'driver/responder'` succeed and `'admin'`/`'dispatcher'` are rejected.
- **`test/registration_test.dart`**:
  - Remove `expect(AppPrefs.instance.accountType, AccountType.resident)` assertion after registration; keep assertion that `'Continue to sign in'` lands on `LoginScreen`.

---

## Verification Checklist
1. Run `flutter analyze` inside `mdrrmo_flutter` and confirm zero errors/warnings for removed symbols or unused imports.
2. Run `flutter test` across the full test suite (`app_smoke_test.dart`, `auth_service_test.dart`, `registration_test.dart`, `unified_login_test.dart`, etc.).
3. Manually verify on device/emulator:
   - Fresh install launches directly to unified `LoginScreen`.
   - Emergency SOS and Guest Report work without logging in.
   - Resident registration creates a resident account and returns to `LoginScreen`.
   - Resident credentials open `ResidentApp`; Driver/Responder credentials open `ResponderApp`.
   - Logging out from either shell returns cleanly to unified `LoginScreen`.
