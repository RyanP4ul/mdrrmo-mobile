# HYOps / MDRRMO Flutter Mobile Application — Complete UI/UX Redesign Plan

> **Document Status:** Pre-Implementation Plan (Awaiting Approval — No Flutter code modified yet)  
> **Target Project:** `d:\Project\workspace_project\mdrrmo\mdrrmo_flutter`  
> **Primary Brand Accent:** Royal Blue (`#4169E1`)  
> **Scope Inspected:** All 72 Dart source files in `lib/`, `pubspec.yaml`, `analysis_options.yaml`, and 25 test files in `test/`  
> **Baseline Static Analysis:** `flutter analyze --no-pub` exited `0` (`No issues found!`)  

---

## 1. Executive Summary

### 1.1 Application Context & Mission
**HYOps / MDRRMO** (`mdrrmo_flutter`) is a mission-critical public safety, emergency dispatch, and municipal service application for Balagtas MDRRMO supporting three distinct live user modes:
1. **Unauthenticated / Guest Citizens** (`SosScreen`, `GuestReportScreen`, `RegisterScreen`, `PasswordRecoveryScreen`)
2. **Registered Residents** (`ResidentApp` / `ResidentShell`: emergency reporting, one-tap SOS voice calling, scheduled municipal transport/assistance requests, history tracking, notifications)
3. **Field Drivers & Responders** (`ResponderApp` / `Shell`: live GPS tracking, WebSocket realtime dispatch updates, active emergency & service assignments, OSRM road navigation + hospital routing, Patient Care Reports, Driver Trip/Fuel Logs, Vehicle Maintenance Reports, Team & Vehicle Roster)

A fourth legacy module (`OperationsApp` + `FleetMapScreen`) remains in `lib/` and is referenced by `test/operations_screen_test.dart`, despite `AuthService._login()` blocking `admin` and `dispatcher` accounts on mobile ("Admin and dispatcher accounts use the website").

### 1.2 Core Design Problems Uncovered
While the underlying business logic, API contracts, idempotency queue (`PendingSubmissions`), Agora voice calling (`VoiceCallController`), WebSocket realtime sync (`DriverRealtime`), and background GPS tracking (`AutomaticDriverTracking`) are thoughtfully engineered, the UI/UX layer suffers from structural fragmentation:
- **Dual-Toolkit Collision:** The codebase mixes `forui` (`FScaffold`, `FHeader`, `FButton`, `FTextFormField`, `FSelect`, `FDialog`, `FLucideIcons`) with raw Material widgets (`AppBar`, `Scaffold`, `TextField`, `DropdownButtonFormField`, `AlertDialog`, `SimpleDialog`, `FilledButton`, `OutlinedButton`, `TextButton`, `ChoiceChip`). Static scan across the 72 Dart files reveals **219 `Icons.*` calls vs. only 50 `AppIcons.*` (Lucide) calls**, **45 raw Material buttons vs. 22 `AppButton`s**, **20 `showDialog`/`AlertDialog`/`SimpleDialog` calls vs. 9 `confirmDialog`s**, and **141 raw `Colors.*` references**.
- **Broken Dark Mode & Inverted Surface Semantics:** `MdrrmoApp` sets `ThemeMode.system`, and `AppTheme` defines a dark palette (`#0B1120` background, `#111827` surface), yet **18 call sites across 10 files** (`main.dart`, `account_screen.dart`, `fleet_map_screen.dart`, `location_access_gate.dart`, `operations_app.dart`, `pending_submissions_screen.dart`, `record_browser_screen.dart`, `record_details_screen.dart`, `search_screen.dart`, `voice_calls_screen.dart`) hardcode light-only tokens (`AppColors.surfaceLight`, `borderLight`, `primarySurface`, `dangerSurface`, `warningSurface`). Worse, `_royalBlueLight` assigns `AppColors.surfaceLight` (`#FFFFFF`) to `FThemeData.colors.background`, inverting canvas and surface depth.
- **Unreachable Core Feature (`AccountScreen`):** `AccountScreen` (profile editing, avatar upload, password change, account deletion request) is only wired in unreachable `OperationsApp`. Neither `ResidentShell` nor Responder `Shell` exposes `AccountScreen` in navigation or the "More" sheet.
- **Map & Workflow Friction in Urgent Scenarios:** `RouteNavigationScreen` stacks address text, two expandable lists (`ExpansionTile`), a search bar, search suggestions, ETA text, wrapped buttons, and `FlutterMap` inside one fixed `Column`—crushing the map on normal phones and hiding ETA/directions altogether when `maxHeight < 480`. `SosScreen` bypasses `AppScaffold`, renders an oversized unstyled red icon (`size: 80`), and leaves zero vertical spacing between its call button, phone number text, and helper caption.
- **Lack of Typographic & Component Discipline:** `AppTheme.buildMaterialTheme()` omits a custom `textTheme`; `appType` offers only five bare sizes without hierarchy or theme-bound color; `lib/` contains **120 inline `TextStyle(` declarations** across **21 arbitrary `fontSize` literals (`10` through `36`)**.

### 1.3 Redesign Direction (Anti-AI-Slop Stance)
This redesign rejects decorative "AI-slop" templates (neon gradients, glassmorphism, floating shadow-heavy cards, gratuitous pill badges, decorative icons next to every field, and card-wrapping every piece of text). Instead, it establishes a **high-clarity civic operations interface**:
- **Intentional Royal Blue (`#4169E1`):** Reserved strictly for primary actions, active navigation states, key interactive links, and focus indicators (~10–15% visual weight). Critical emergencies/SOS strictly own Semantic Red (`#DC2626`).
- **Crisp Neutral Hierarchy:** Flat `#F8FAFC` light / `#0B1120` dark canvas, `#FFFFFF` / `#111827` grouped surfaces, `1px` hairline borders (`#E2E8F0` / `#263244`), restrained radii (`6px` / `8px` / `12px`), and subtle list dividers instead of repetitive standalone boxed cards.
- **Speed & One-Handed Field Ergonomics:** Zero artificial launch delay, persistent top-level SOS & Account access, full-bleed map routing with draggable bottom sheets, native pickers instead of raw ISO timestamp typing, and non-blocking offline status banners that preserve emergency capabilities.

---

## 2. Current UI/UX Audit

Every issue below identifies: **(1) What is wrong**, **(2) Why it hurts usability**, **(3) What should change**, and **(4) How the redesign improves UX**, ordered by severity (`P0` Critical → `P3` Low).

### Severity Legend
- **P0 (Critical):** Blocks core functionality, compromises emergency speed/safety, or breaks contrast/accessibility severely.
- **P1 (High):** Causes substantial friction, visual inconsistency, input errors, or performance/lifecycle degradation.
- **P2 (Medium):** Creates visual clutter, redundant taps, or unclear state feedback.
- **P3 (Low):** Minor polish, copy, or structural cleanup opportunities.

---

### Audit Findings

#### 1. Account & Profile Screen Unreachable for All Live Mobile Users — **P0 (Critical)**
- **What is wrong:** `AccountScreen` (`lib/screens/account_screen.dart`) is only instantiated inside `OperationsApp` (`lib/screens/operations_app.dart:92`), which is unreachable via `AuthService` mobile login. Neither `ResidentShell` (`resident_shell.dart`) nor Responder `Shell` (`driver-responder/shell.dart`) provides an entry point in the header, bottom bar, or "More options" modal sheet (which only offers Search, Pending submissions, Reports authored [responder], and Log out).
- **Why it negatively affects usability:** Residents and field responders cannot update their phone number, edit name/avatar, change their password after sign-in, view registration status details, or request account deletion inside the mobile app.
- **What should be changed:** Expose `AccountScreen` cleanly from a top-bar profile/avatar trigger (or first item in the consolidated "More / Account" sheet) in both `ResidentShell` and `ResponderShell`.
- **How the redesign improves UX:** Restores full self-service account management in 1–2 taps without expanding bottom navigation beyond 4 tabs.

#### 2. `RouteNavigationScreen` Map Crushing & Small-Viewport Information Loss — **P0 (Critical)**
- **What is wrong:** `RouteNavigationScreen` (`lib/screens/route_navigation_screen.dart`) packs incident address text, `ExpansionTile("Recommended hospitals")` with a fixed-height `ListView`, search `TextField`, search suggestions `ListView`, `FlutterMap` (`Expanded`), ETA text, `ExpansionTile("Road directions")`, and a `Wrap` of `TextButton`s into a single vertical `Column`. When `constraints.maxHeight < 480`, `compact` mode hides ETA summary and turn-by-turn directions entirely.
- **Why it negatively affects usability:** Expanding hospitals or road directions compresses `FlutterMap` to an unusable strip during active ambulance driving/navigation. Landscape or small screens (`<480dp` height) lose ETA and step-by-step instructions completely. Wrapped `TextButton`s blend primary progression/routing actions with secondary map toggles.
- **What should be changed:** Refactor `RouteNavigationScreen` into a **full-bleed map layout** (`Stack`) with: (a) compact floating top search/destination pill + back button, (b) floating right-rail map controls (`Recenter`, `Hospitals`), and (c) an anchored, expandable `DraggableScrollableSheet` holding ETA, current next-turn banner, hospital switcher, and road directions.
- **How the redesign improves UX:** Guarantees >=60% continuous map visibility at all times, keeps ETA and next maneuver readable in compact viewports, and gives drivers thumb-reachable one-handed sheet controls.

#### 3. `OfflineSosGate` Full-Screen Blocking Overlay — **P0 (Critical)**
- **What is wrong:** `OfflineSosGate` (`lib/main.dart`, `lib/screens/sos_screen.dart`) wraps the entire `MaterialApp` child and replaces the active screen (`Offstage`) with `SosScreen(offline: true)` whenever the 5-second `InternetConnection` HTTP probe fails.
- **Why it negatively affects usability:** During patchy municipal mobile data (common during storms/floods or indoors), a responder reviewing cached dispatch details, filling out a `DriverFormScreen` / `EmergencyFormScreen`, or a resident attempting to inspect `PendingSubmissionsScreen` is abruptly kicked out of their active workflow into a single blocked offline screen—even if only one probe timed out.
- **What should be changed:** Replace full-screen route replacement with a **persistent, non-blocking top Offline Connectivity Banner** integrated at the shell/app level offering two immediate 1-tap actions: **Call SOS (`tel:` / cellular fallback)** and **View Queued Submissions (`PendingSubmissionsScreen`)**. Keep offline `SosScreen` easily launchable via 1 tap without destroying current screen state.
- **How the redesign improves UX:** Preserves emergency cellular calling accessibility in offline conditions while letting residents and responders continue reading cached assignments, forms, and pending submissions without losing context.

#### 4. `SosScreen` Layout Breakdown & Duplicated SOS Surfaces — **P0 (Critical)**
- **What is wrong:**
  1. `SosScreen` (`lib/screens/sos_screen.dart`) uses raw Material `Scaffold` + `AppBar` instead of `AppScaffold` / `pushedHeader`, displays a harsh `Icon(Icons.sos, size: 80, color: Colors.red)` (`Colors.red`), an unstyled `FilledButton.icon`, and places two `Text` blocks directly beneath with **0px vertical gap** (`SizedBox` omitted). Guest info fields use raw `ExpansionTile` + raw `TextField`s.
  2. `ResidentHomeScreen` (`resident/home_screen.dart`) displays an SOS button in the top header **AND** a second giant 156x156 circular red SOS button inside a large card occupying half the above-the-fold screen.
- **Why it negatively affects usability:** On `SosScreen`, cramped text directly touches the button edge, undermining visual trust during high-stress emergencies. On `ResidentHomeScreen`, duplicating SOS in the top bar and hero card bloats scroll depth and forces secondary tasks (`Services`, `Recent reports`) below the fold.
- **What should be changed:** Unify `SosScreen` under `AppScaffold` with structured spacing (`16px`–`24px`), clear action hierarchy (Primary Internet Voice SOS -> Cellular Dialer fallback -> Clean collapsible Guest Identification section using `AppTextField`), and clear approval/connectivity messaging. On `ResidentHomeScreen`, keep **one intentional SOS entry bar/button** cleanly paired with concise emergency status context and immediate quick actions.
- **How the redesign improves UX:** Eliminates visual clutter under panic, ensures crisp visual separation and contrast in both light and dark modes, and brings resident recent activity above/near the fold.

#### 5. Dark Mode Contrast Breakdown & Surface Token Inversion — **P0 (Critical)**
- **What is wrong:**
  1. `lib/ui/app_theme.dart` sets `_royalBlueLight.colors.background = AppColors.surfaceLight` (`#FFFFFF`), while `AppScaffold` paints `AppColors.backgroundLight` (`#F8FAFC`). Any widget reading `context.theme.colors.background` (like `Surface`) gets `#FFFFFF` instead of a theme-explicit surface token.
  2. **18 code locations outside `app_theme.dart`** hardcode light-only colors (`AppColors.surfaceLight`, `borderLight`, `primarySurface`, `dangerSurface`, `warningSurface`): e.g. `main.dart:110–112`, `account_screen.dart:156, 445`, `fleet_map_screen.dart:97, 106`, `location_access_gate.dart:232, 263`, `pending_submissions_screen.dart:106, 130`, `record_browser_screen.dart:247`, `record_details_screen.dart:892, 999`, `search_screen.dart:21`, `voice_calls_screen.dart:315–316, 361, 373`, `operations_app.dart:111, 1272`.
  3. **15 hardcoded `Color(0x...)` literals** and **141 `Colors.*` usages** appear across feature screens (`res_widgets.dart:54` `Color(0xFFCA8A04)`, `voice_calls_screen.dart` `Colors.white`, etc.).
- **Why it negatively affects usability:** When OS dark mode is active (`ThemeMode.system`), bright `#FFFFFF`, `#EEF2FF`, and `#FEF2F2` boxes flash across `#0B1120` dark screens, producing illegible light-on-light or jarring high-glare patches for night-shift ambulance drivers and responders.
- **What should be changed:** Introduce a brightness-aware `ThemeExtension<MdrrmoColors>` (`canvas`, `surface`, `surfaceSubtle`, `border`, `brandTint`, `dangerTint`, `warningTint`, `successTint`, `textPrimary`, `textSecondary`, `textMuted`) and eliminate every hardcoded light-surface/color literal in `lib/`.
- **How the redesign improves UX:** Guarantees WCAG-compliant contrast in both daytime sunlight and night-shift dark mode without per-screen workarounds.

#### 6. Dual-Toolkit UI Fragmentation (Forui + Raw Material Drift) — **P1 (High)**
- **What is wrong:** While `kit.dart` wraps Forui (`FButton`, `FTextFormField`, `FSelect`, `FDialog`, `FLucideIcons`), screens bypass `kit.dart` heavily: **219 Material `Icons.*` vs. 50 `AppIcons.*`**, **45 raw Material buttons (`FilledButton`/`OutlinedButton`/`TextButton`) vs. 22 `AppButton`s**, **20 `showDialog`/`AlertDialog`/`SimpleDialog` vs. 9 `confirmDialog`s**, **6 raw `Scaffold`/`AppBar`s**, and **7 raw `TextField`/`DropdownButtonFormField`s**.
- **Why it negatively affects usability:** Inputs, dialogs, back arrows, dropdowns, and buttons behave, animate, size, and style differently from screen to screen (e.g., `RegisterScreen` uses Material `AlertDialog` while `LogoutAction` uses Forui `FDialog`; `PasswordRecoveryScreen` and `RecordBrowserScreen` use raw Material `TextField`s without `AppTextField` border/focus styling).
- **What should be changed:** Standardize every screen onto unified `lib/ui/` primitives (`AppScaffold`, `AppHeader`, `AppButton`, `AppTextField`, `AppSelect`, `AppDialog`, `AppSheet`, and `AppIcons` backed exclusively by `FLucideIcons`).
- **How the redesign improves UX:** Creates predictable visual rhythm, uniform focus/error states, and consistent iconography across every flow.

#### 7. Artificial 2.4-Second Splash Delay & Auth Onboarding Friction — **P1 (High)**
- **What is wrong:** `SplashScreen` (`splash_screen.dart`) enforces an artificial `Timer(Duration(milliseconds: 2400))` on top of network `getMe()` latency. On `RoleSelectScreen`, the Guest Emergency Report button is hidden inside `AnimatedSize`/`AnimatedOpacity` and only appears *after* selecting `Resident`. On `LoginScreen`, a large logo + `"MDRRMO"` display title + role pill + `"Back to role selection"` button sit above the sign-in form, pushing fields and `"Sign in"` below the keyboard fold on compact screens.
- **Why it negatively affects usability:** Delays emergency/responder launch by ~2.4s every cold boot. An unauthenticated citizen in an emergency must first read and select "Resident" just to discover they can report without an account.
- **What should be changed:** Replace the 2.4s timer with immediate parallel initialization (`AuthService.hasToken()` / `getMe()`) + fast cross-fade (<=250ms). On `RoleSelectScreen`, always surface **Emergency SOS / Guest Report** as a steady secondary safety bar at the top or bottom without conditional hiding. Compact the `LoginScreen` header using the standard back navigation bar (no duplicate `"Back to role selection"` text button) and ensure proper `KeyboardAvoiding` scroll clearance.
- **How the redesign improves UX:** Cuts cold-start time-to-interaction by ~2 seconds and makes emergency reporting immediately discoverable for guests.

#### 8. `SearchScreen` Unnecessary Hop & `RecordBrowserScreen` Filter Bloat — **P1 (High)**
- **What is wrong:** Tapping "Search records" opens `SearchScreen` (`search_screen.dart`), which is purely a menu of 3 giant full-width Royal Blue `AppButton`s (`Reports`, `Schedules`, `Notifications`) leading to `RecordBrowserScreen`. Inside `RecordBrowserScreen`, a full filter panel (search box, `From`/`To` date buttons, `Status` dropdown, `Apply`/`Clear` buttons) sits fixed at the top of the `ListView`, consuming over half the viewport before the first record appears.
- **Why it negatively affects usability:** Forces an extra navigation push/pop just to switch between record types, and hides search results beneath a tall static filter stack on mobile screens.
- **What should be changed:** Remove `SearchScreen` as a separate menu step; fold a top `Segmented` control (`Reports` | `Schedules` | `Notifications`) + sticky search bar + active-filter chip strip + bottom-sheet `Filters` modal directly into `RecordBrowserScreen`.
- **How the redesign improves UX:** Cuts 1 screen hop and gives ~70%+ vertical viewport space to actual search results.

#### 9. Touch Target Violations & Uncontrolled Typographic Scale — **P1 (High)**
- **What is wrong:**
  - `home_screen.dart` `_AssignmentActionTile` uses `minimumSize: Size.zero` with `padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8)` and `fontSize: 11`.
  - `StepperBar` (`kit.dart`) uses `22x22` circles with `10.5px` labels.
  - Driver map labels (`home_screen.dart:806`) and badges across multiple screens drop to `10px–11.5px`.
  - Across `lib/`, **120 inline `TextStyle(` declarations** use **21 distinct `fontSize` literals** (`10, 10.5, 11, 11.5, 12, 12.5, 13, 13.5, 14, 14.5, 15, 16, 17, 18, 20, 21, 22, 24, 26, 30, 36`).
- **Why it negatively affects usability:** Sub-48dp action tiles inside moving ambulances cause mis-taps between `Navigate`, `Details`, and `Patient Care`. Text under `12px` degrades legibility in sunlight and fails WCAG / Material touch and type accessibility.
- **What should be changed:** Enforce a `48dp` minimum hit area on all interactive controls (`MaterialTapTargetSize.padded` or explicit `minHeight: 48` / `48x48` icon buttons), replace `21` scattered font sizes with a 6-token `TextTheme`, enforce `12sp` floor on functional UI labels (`14sp`+ for action controls), and add tabular numerals (`tabularFigures`) for ETAs, times, coordinates, and fuel liters.
- **How the redesign improves UX:** Reliable one-handed taps in moving vehicles and predictable scanning at any system text-scale setting.

#### 10. Hostile Field Forms, Duplicate Driver Form & Validation Gaps — **P1 (High)**
- **What is wrong:**
  1. **Duplicate Driver Forms:** `DriverFormScreen` (`driver-responder/driver_form_screen.dart`) and `StandaloneDriverFormScreen` (`record_details_screen.dart:1034`) implement the same trip/fuel log with divergent field UX.
  2. **Hostile `ApiEditScreen` & `PatientCareScreen`:** `ApiEditScreen` requires users to manually type raw ISO-8601 strings (`YYYY-MM-DDTHH:mm:ssZ`), `YYYY-MM-DD`, `HH:mm`, and raw decimal `latitude`/`longitude` coordinates into plain text fields. `PatientCareScreen` dumps 17 flat dot-prefixed keys into `ApiEditScreen` with no clinical grouping.
  3. **`EmergencyFormScreen` UX Bugs:** `confirmDialog` sets `destructive: true` (alarming red button) for normal report submission; lacks a "Use my current GPS location" button despite active `DriverTracking`; places server `_error` at the very bottom below all inputs.
  4. **`DriverFormScreen` Ambiguity:** Computed fuel totals (`Total Available Fuel`, `Remaining Fuel`) remain editable numeric inputs alongside a manual text date field + separate icon button.
  5. **`ResidentReportScreen` Validation & Back Flow:** Step 1 advances immediately on single card tap with no review step; Step 2 lacks a `FormState.validate()` call on submit (relying on `snack(...)` bottom banners when untouched required fields are empty); `PopScope` discards from Step 2 instead of returning to Step 1.
- **Why it negatively affects usability:** High error rates under field stress, lost form progress on accidental taps, confusing red warnings on standard confirmations, and tedious typing of timestamps/coordinates on mobile keyboards.
- **What should be changed:** Delete `StandaloneDriverFormScreen` in favor of a single `DriverFormScreen`; upgrade `ApiEditScreen` with native date/time pickers, visual coordinate pinners, and clinical section headers for `PatientCareScreen`; add 1-tap GPS pin + top error banner + neutral confirmation to `EmergencyFormScreen`; mark computed fuel fields read-only calculated summaries in `DriverFormScreen`; wire `Form` validation + clean step-back navigation in `ResidentReportScreen`.
- **How the redesign improves UX:** Cuts typing by >50% in field reports, prevents data loss, and surfaces validation inline right where the user needs to fix input.

#### 11. Double 30s Polling Timers & Shell Progress-Bar Flicker — **P1 (High)**
- **What is wrong:** `ResponderApp` wraps `ResponderShell` in `DataRefresh` (30s timer), and `HomeAssignmentsSection` (`home_assignments_section.dart`) wraps itself in a **second nested `DataRefresh`** (also 30s). Furthermore, both `ResidentShell` and Responder `Shell` render a `LinearProgressIndicator` directly at the top of the body whenever `state.isLoading` is true—including every silent 30-second background poll.
- **Why it negatively affects usability:** Wastes battery/network on duplicate API calls in the responder home view and causes repetitive visual flicker across the top edge every 30 seconds while users read or scroll.
- **What should be changed:** Remove the redundant `DataRefresh` in `HomeAssignmentsSection`; distinguish initial blocking load (`isInitialLoading`) from silent background refresh (`isRefreshing`) so periodic refreshes update seamlessly without flashing a progress bar.
- **How the redesign improves UX:** Eliminates distracting 30s flicker and halves unnecessary home-tab polling load.

#### 12. Card Overuse, Pill Clutter & Duplicated Role Widget Kits — **P2 (Medium)**
- **What is wrong:**
  - `ResidentWidgets` (`resident_widgets.dart`) and `ResponderWidgets` (`responder_widgets.dart`) re-implement nearly identical panels, headings, tags, empty states, and shortcuts (`ResidentPanel`/`ResponderPanel` both wrapping `Surface`).
  - `ResidentHomeScreen` stacks header `"Balagtas Rescue"`, badge `"BALAGTAS RESCUE"`, SOS card, 3 shortcut cards, and recent report cards—making every element a bordered card with repetitive `"View report ->"` text footers.
  - `ResponderRecordsScreen` displays up to 3 pills + dot + reference + timestamp per notification card (`RESPONSE UPDATE`, `Unread`, `Report #id`, `timeAgo`).
- **Why it negatively affects usability:** Visual noise slows down scanning; important urgency cues (Critical vs Low, Unread vs Read) get drowned out among decorative uppercase category tags and redundant arrow links.
- **What should be changed:** Consolidate `ResidentWidgets` and `ResponderWidgets` into shared `lib/ui/` grouped list sections and list rows separated by `1px` dividers; reserve pills strictly for actionable/meaningful **state** (status, priority, unread dot); remove redundant `"View details ->"` links from whole-row tappable items (use subtle chevron icon `AppIcons.chevronRight` at trailing edge).
- **How the redesign improves UX:** Dramatically cleaner density, clearer visual hierarchy, and faster list scanning without AI-template card fatigue.

#### 13. `ScheduleScreen` Tab Overload, Per-Keystroke Rebuild & Status Color Bug — **P2 (Medium)**
- **What is wrong:** `Resident` `ScheduleScreen` combines two distinct modes ("My requests" vs "New request") via inline `ChoiceChip`s inside a `ListView`; `initState` attaches `_destination.addListener(() => setState(() {}))` causing a full-screen rebuild on every keystroke; `ScheduleRequest` status badge colors (`resident_widgets.dart` / `schedule_screen.dart`) only check `'confirmed'` / `'completed'`, coloring `'cancelled'` and `'declined'` as amber warning with raw lowercase text (`pending`, `confirmed`). `_PurposeChip` paints 6 competing saturated colors.
- **Why it negatively affects usability:** Keyboard input stutters on older devices due to full-tree rebuilds; cancelled or declined municipal requests look like "warnings" instead of neutral/closed or rejected states.
- **What should be changed:** Separate "My requests" and "New request" using a clean top `Segmented` control (or `TabBar`); use `ValueListenableBuilder` / `FormField` instead of page-wide `setState` listeners; normalize status labels (`Pending`, `Confirmed`, `En Route`, `Cancelled`, `Declined`) with consistent semantic colors; unify `_PurposeChip` to neutral outline chips with single Royal Blue `#4169E1` selected state.
- **How the redesign improves UX:** Smoother typing performance, intuitive tab mental model, and accurate status recognition.

#### 14. `VoiceCallsScreen` Form-Like Layout & Lifecycle Fragility — **P2 (Medium)**
- **What is wrong:** `VoiceCallsScreen` (`voice_calls_screen.dart`) looks like a settings form (`Surface` cards with `OutlinedButton.icon` inside `Wrap` for Mute/Speaker/Leave), mixes raw `AlertDialog` instead of `confirmDialog`, uses hardcoded `Colors.white` / `Theme.of(context).colorScheme.error`, shows no active call duration timer, and automatically terminates an active Agora voice call whenever the app is paused/backgrounded (`didChangeAppLifecycleState` -> `AppLifecycleState.paused`).
- **Why it negatively affects usability:** During an emergency call, accidentally turning off the screen or switching apps to check a map/message hangs up on the dispatcher; small wrapped `OutlinedButton`s are harder to hit than a dedicated call dock.
- **What should be changed:** Design a purposeful call stage: status header + live elapsed call duration (`tabularFigures`) + docked bottom audio control bar (`Mute`, `Speaker`, `End Call` circular 56dp controls); standardize confirmations onto `confirmDialog`; add clear warning banner/state messaging around background lifecycle constraints (while preserving audio/permission safety).
- **How the redesign improves UX:** Immediately recognizable voice-call ergonomics and larger, safer controls during urgent voice coordination.

#### 15. `PendingSubmissionsScreen` & `LocationAccessGate` Clarity — **P2 (Medium)**
- **What is wrong:** `PendingSubmissionsScreen` (`pending_submissions_screen.dart`) only shows `record.label` + `record.location` (hiding timestamp and summary), has a double `setState(() => _error = ...)` overwrite around `await _load()` (lines 85–88), and provides no way to inspect details or discard a permanently rejected local item. `LocationAccessGate` (`location_access_gate.dart`) renders a dense ~65-word paragraph above 3 stacked buttons (`AppButton` + 2 `TextButton`s).
- **Why it negatively affects usability:** Users staring at old queued items cannot tell when they were created or safely clear a stale duplicate; responders blocked by GPS permission see a wall of text instead of actionable 1-step status checks.
- **What should be changed:** Show submission timestamp, concise payload summary, `"Retry all"` / per-item `"Confirm"`, and a `confirmDialog`-guarded `"Discard"` action in `PendingSubmissionsScreen` (fixing the error assignment sequence). Restructure `LocationAccessGate` into a compact 2-step status checklist (`Location Service` + `App Permission`) with one clear primary action button and secondary link.
- **How the redesign improves UX:** Faster resolution of offline queue conflicts and GPS permission issues.

#### 16. `OperationsApp` & `FleetMapScreen` Unreachable Code Ambiguity — **P2 (Medium)**
- **What is wrong:** `operations_app.dart` (1,333 lines) and `fleet_map_screen.dart` (244 lines) are never reachable at runtime because `AuthService._login()` rejects non-resident/non-driver accounts on mobile. They also rely heavily on legacy patterns (`SimpleDialog` lists, stacked 12-button menu, raw `entry.key: entry.value` map dumps).
- **Why it negatively affects usability / maintainability:** Bloats bundle surface, duplicates detail/navigation patterns, and creates maintenance confusion for developers vs. active resident/responder screens.
- **What should be changed:** Explicitly isolate or archive `OperationsApp`/`FleetMapScreen` behind a dedicated legacy/internal boundary (keeping `test/operations_screen_test.dart` green if retained, or confirming deprecation with stakeholders).
- **How the redesign improves UX:** Keeps design system effort focused 100% on the actual mobile end-user and field responder workflows.

#### 17. `MaintenanceFormScreen` Combined Form/History & Error Silence — **P3 (Low)**
- **What is wrong:** `MaintenanceFormScreen` embeds a `"Recent maintenance reports"` history feed directly below the submission form, swallows offline history fetch errors (`catch (_) {}`), and mixes a Material `CheckboxListTile` inside a Forui `FormGroup`.
- **Why it negatively affects usability:** Scrolling past long past-report cards clutters an active defect report form; silent failure gives no hint if history failed to sync.
- **What should be changed:** Move `"Recent reports"` to a secondary tab/pill or top-right history sheet button (`Recent (N)`), style the out-of-service recommendation toggle as an accessible `SwitchListTile`/styled `AppSwitchRow`, and surface subtle inline refresh status when offline.
- **How the redesign improves UX:** Focused defect submission workflow with clear inspection of prior vehicle reports when needed.

#### 18. Inconsistent Header Identity & Back-Stack Reset on `LoginScreen` — **P3 (Low)**
- **What is wrong:** `ResidentShell` uses `"Balagtas Rescue"` while Responder `Shell` uses `"MDRRMO"`. `LoginScreen` intercepts back navigation via `PopScope(canPop: false)` and pushes a brand-new `RoleSelectScreen` via `pushReplacement` instead of naturally popping back.
- **Why it negatively affects usability:** Breaks natural navigation history expectations and creates slight branding inconsistency between screens.
- **What should be changed:** Unify app header framing (`Balagtas MDRRMO` + subtle role context label when needed) and preserve clean navigation stack behavior (`maybePop` / route-based fallback only when stack is empty).
- **How the redesign improves UX:** Predictable Android system-back behavior and unified civic brand voice.

---

## 3. Screen-by-Screen Redesign Recommendations

All screens, shells, gates, dialogs, and bottom sheets in `mdrrmo_flutter/lib/` are covered below.

### Group A: App Bootstrap, Splash & Global Gates

#### 1. `AppStartup` (`lib/main.dart`)
- **Current Purpose:** Initializes `.env`, `AppPrefs`, `DispatcherPhone`, and token presence before booting `MdrrmoApp`; displays loading spinner or full-screen error box if bootstrap fails.
- **Existing Problems:** Startup error box hardcodes `AppColors.surfaceLight` and `borderLight`, ignoring OS dark mode; mixes raw `MaterialApp` error scaffolding before `FTheme` loads.
- **Proposed Layout Improvements:** Minimal centered layout with 56dp logo mark, restrained activity indicator, and theme-adaptive error card (`ThemeData` light/dark aware) with clear `"Retry startup"` primary button.
- **Navigation:** Auto-advances straight to `MdrrmoApp` / session restoration.
- **Recommended Components:** `AppStateView` error mode, `FilledButton` / `AppButton` styled cleanly.
- **Expected Improvements:** Eliminates harsh white-card flash in dark mode during startup failure.
- **Priority:** `P1 High`

#### 2. `SplashScreen` (`lib/screens/splash_screen.dart`)
- **Current Purpose:** Restores authenticated user via `AuthService.getMe()` and routes to `ResidentApp`, `ResponderApp`, `RoleSelectScreen`, or `LoginScreen`.
- **Existing Problems:** Hardcoded `Timer(2400ms)` delays app usability on every cold launch even when network returns faster or token is absent; adds unnecessary `"MUNICIPAL PUBLIC SAFETY"` pill badge and scale/fade animation delay.
- **Proposed Layout Improvements:** Clean centered `LogoMark` (`64dp`), concise `"Balagtas MDRRMO"` title + subtle activity bar; on failure, inline retry card with immediate **Emergency SOS / Guest Report** fallback button so a failed token check doesn't trap citizens.
- **Navigation:** Execute `AuthService.hasToken()` / `getMe()` immediately in `initState` with zero artificial floor (`2400ms` removed); transition cleanly once resolved.
- **Recommended Components:** `LogoMark`, `CircularProgressIndicator.adaptive`, inline `AppStateView` + Emergency quick-exit button.
- **Expected Improvements:** ~2.0–2.4s faster time-to-interactive for responders and residents in urgent situations.
- **Priority:** `P1 High`

#### 3. `OfflineSosGate` (`lib/main.dart`, `lib/services/internet_connection.dart`)
- **Current Purpose:** Watches `InternetConnection` (5s probe) and interrupts UI when offline to ensure citizens can reach dispatch via cellular `tel:`.
- **Existing Problems:** Uses `Offstage` to completely hide the active screen behind `SosScreen(offline: true)` whenever connectivity drops—wiping active forms, cached dispatch screens, and pending queue access.
- **Proposed Layout Improvements:** Replace full-screen takeover with a slim, high-contrast **Persistent Offline Bar** pinned above shell content (`Semantic.warning` / `Semantic.danger` border-bottom strip) displaying `"Offline mode · Cellular SOS still works"` + compact `"SOS"` and `"Queued (N)"` actions. Provide full-screen offline SOS only on explicit tap or unauthenticated offline startup.
- **Navigation:** Non-destructive overlay preserving the underlying `Navigator` stack; tapping `"SOS"` pushes `SosScreen(offline: true)`; tapping `"Queued"` pushes `PendingSubmissionsScreen`.
- **Recommended Components:** `AppOfflineBanner`, `PendingSubmissions` badge count hook.
- **Expected Improvements:** Prevents abrupt work loss during transient signal drops in rural barangays or indoors.
- **Priority:** `P0 Critical`

#### 4. `LocationAccessGate` (`lib/screens/location_access_gate.dart`)
- **Current Purpose:** Ensures Responder Dispatch tab has OS GPS enabled and permission granted for live tracking and emergency dispatch accuracy.
- **Existing Problems:** Replaces the entire Dispatch tab with a ~65-word explanatory paragraph, hardcoded `AppColors.primarySurface`/`dangerSurface`, and 3 vertically stacked buttons (`AppButton` + 2 `TextButton`s).
- **Proposed Layout Improvements:** Crisp 2-row readiness checklist inside one clean surface:
  1. `Device GPS` (Active / Turned Off)
  2. `Location Permission` (Granted / Needed)
  With **1 clear primary CTA** tailored to the actual failing step (`"Enable location permission"` or `"Open location settings"`) and **1 secondary `"Recheck status"`** outline button.
- **Navigation:** Automatic seamless transition straight into Responder Home once both checks pass.
- **Recommended Components:** `AppStateView`, grouped readiness rows with Lucide status icons (`AppIcons.check`, `AppIcons.alert`), `AppButton`.
- **Expected Improvements:** Responders diagnose GPS vs. permission blockers in <2 seconds instead of reading dense paragraphs.
- **Priority:** `P2 Medium`

---

### Group B: Onboarding, Auth & Unauthenticated Safety Flows

#### 5. `RoleSelectScreen` (`lib/screens/role_select_screen.dart`)
- **Current Purpose:** First-run role picker (`Resident` vs `Driver / Responder`) plus guest emergency entry.
- **Existing Problems:** Guest report banner hides conditionally behind `selected == AccountType.resident`; top-right `"SOS"` uses low-emphasis `TextButton.icon`; uses Material `AppBar` + `FilledButton` instead of `AppButton`; large promotional padding pushes CTA close to bottom edge.
- **Proposed Layout Improvements:**
  - Clean headerless `SafeArea` canvas with centered compact `LogoMark` (`48dp`), `"Balagtas MDRRMO"`, and concise prompt (`"Select how you use the app"`).
  - Two clean selectable role rows (`Resident` — report emergencies, request assistance; `Driver / Responder` — receive dispatches, track ambulance routes) using crisp 1px border + Royal Blue `#4169E1` selected border/radio check (no oversized bloated cards).
  - Always-visible **Emergency Assistance Strip** directly above/below role selection: compact `SOS Call` (Semantic Red outline/tonal) and `Report as Guest` (neutral outline) so citizens never hunt for emergency help.
  - Bottom docked `Continue` primary `AppButton`.
- **Navigation:** Tapping `Continue` navigates to `LoginScreen(account: selected)` (saving role in `AppPrefs`); `SOS Call` pushes `SosScreen(guest: true)`; `Report as Guest` pushes `GuestReportScreen`.
- **Recommended Components:** `AppScaffold`, `AppSelectableTile`, `AppButton` (primary + destructive/emergency outline).
- **Expected Improvements:** Zero hidden emergency paths; ~30% tighter vertical balance; immediate guest discoverability.
- **Priority:** `P1 High`

#### 6. `LoginScreen` (`lib/screens/login_screen.dart`)
- **Current Purpose:** Authenticates Residents or Drivers/Responders for the selected role via `AuthService.login()`.
- **Existing Problems:** Material `AppBar` + low-emphasis SOS `TextButton`; excessive top hero block (56px icon container + 26px display title + role pill + redundant `"Back to role selection"` `TextButton`) shoves inputs/CTA below small keyboards; `PopScope(canPop: false)` forcibly replaces route stack.
- **Proposed Layout Improvements:** Standard `pushedHeader` with back arrow to Role Selection + subtle `"SOS"` trailing danger pill/button (`AppIcons.phoneCall` + `"SOS"`). Compact page title (`"Sign in"` + 1-line role context subtitle `"Resident account"` / `"Responder & Driver account"`). Directly place clean `Email`, `Password`, inline `"Forgot password?"` link, `Sign in` primary button, and `"Create resident account"` link (for residents only).
- **Navigation:** Standard `Navigator.maybePop()` returning cleanly to `RoleSelectScreen` (falling back to replacement only if `canPop == false`); routes to `ResidentApp`, `ResponderApp`, `RegisterScreen`, or `PasswordRecoveryScreen`.
- **Recommended Components:** `AppScaffold`, `AppHeader`, `AppTextField`, `AppPasswordField`, `AppButton`.
- **Expected Improvements:** Eliminates scrolling to hit `"Sign in"` on 360x640 phones when keyboard opens; preserves clean navigation history.
- **Priority:** `P1 High`

#### 7. `RegisterScreen` (`lib/screens/register_screen.dart`) + Privacy Policy Dialog
- **Current Purpose:** Self-service Resident account registration with password validation and Data Privacy Act consent (`AuthService.getPolicy()`).
- **Existing Problems:** Submit button stays disabled silently while policy loads; uses Material `AlertDialog` for policy modal; stacks 7 inputs inside 1 long group without visual separation between Personal Info, Account Security, and Consent.
- **Proposed Layout Improvements:** Group cleanly into two compact sections: **Personal Details** (`First Name`, `Last Name`, `Contact Number`, `Email`) and **Security & Consent** (`Password`, `Confirm Password`, checkbox + `"Read privacy notice"` trigger). Display policy load failures as an inline banner with `"Retry policy"` inside the consent group rather than disabling blindly. Replace Material `AlertDialog` with unified scrollable `AppModalSheet` / `AppDialog`.
- **Navigation:** Pushes from `LoginScreen`; returns on success or routes seamlessly into `ResidentApp`/login confirmation.
- **Recommended Components:** `FormPage`, `FormGroup`, `AppTextField`, `AppPasswordField`, `AppCheckboxRow`, `AppSheet`.
- **Expected Improvements:** Faster scanability across 7 inputs and dark-mode-safe readable privacy modal.
- **Priority:** `P2 Medium`

#### 8. `PasswordRecoveryScreen` (`lib/screens/account_screen.dart`)
- **Current Purpose:** Two-step forgot-password flow (`/auth/mobile/password/forgot` -> `/auth/mobile/password/reset`).
- **Existing Problems:** Uses raw Material `TextField` instead of `AppTextField`; places `"Email reset code"` as an understated `TextButton` above primary `"Enter reset code"` button; opens a separate `ApiEditScreen` raw text form for step 2 (`token`, `new_password`, `confirm_password`).
- **Proposed Layout Improvements:** Single clean two-stage stepper within one dedicated screen (Stage 1: Enter email -> `"Send reset code"` primary button -> inline success confirmation; Stage 2: Enter 6-digit/token code + new password + confirm password with live validation -> `"Reset password"` primary button). Preserve exact `/password/forgot` and `/password/reset` payloads.
- **Navigation:** Pushed from `LoginScreen` `"Forgot password?"`; pops cleanly back to `LoginScreen` on completion.
- **Recommended Components:** `FormPage`, `AppTextField`, `AppPasswordField`, `AppButton`, `AppBanner`.
- **Expected Improvements:** Removes awkward jump to generic `ApiEditScreen` and makes step 1 -> step 2 flow intuitive.
- **Priority:** `P2 Medium`

#### 9. `SosScreen` (`lib/screens/sos_screen.dart`)
- **Current Purpose:** High-urgency voice SOS initiator (`VoiceCallsScreen(autoStartSos: true)`) + cellular `tel:` dispatcher fallback, supporting offline mode and unauthenticated/unapproved guests.
- **Existing Problems:** Raw Material `Scaffold`/`AppBar`; giant harsh `Colors.red` `Icons.sos` (`size: 80`); unstyled `FilledButton.icon`; **0px vertical spacing** between button, phone text, and caption; raw `ExpansionTile` + raw `TextField`s for guest details.
- **Proposed Layout Improvements:**
  - Unified `AppScaffold` with crisp header (`"Emergency SOS"`).
  - Top contextual banner when offline (`"No internet — use cellular call below"`) or when guest/unapproved.
  - Focal action block (not bloated): clean **Semantic Red (`#DC2626`) Primary Emergency CTA (`56dp` height)** (`AppIcons.phoneCall` + `"Call MDRRMO Dispatch"` when online, or `"Dial Emergency Line"` when offline), followed cleanly by `16px` gap, Secondary outline fallback button (`"Call via Mobile Network · <number>"` tapping `tel:`), and concise `13sp` response reassurance note.
  - Clean bordered accordion section (`"Optional caller info"`, expanded only if guest wants to prefill name/contact/address via `AppTextField` before calling).
- **Navigation:** Accessed from `RoleSelectScreen`, `LoginScreen`, `GuestReportScreen`, `ResidentShell` top bar, and `AppOfflineBanner`; starts `VoiceCallsScreen(autoStartSos: true)` or `tel:` launcher.
- **Recommended Components:** `AppScaffold`, `AppHeader`, `AppBanner`, `AppButton` (56dp emergency variant), `AppDisclosureSection`, `AppTextField`.
- **Expected Improvements:** Zero layout collisions, calm high-trust hierarchy under stress, full dark mode & dynamic type support.
- **Priority:** `P0 Critical`

#### 10. `GuestReportScreen` (`lib/screens/guest_report_screen.dart`)
- **Current Purpose:** Allows unauthenticated citizens to submit an emergency report via `ResidentReportScreen(guest: true)`.
- **Existing Problems:** Uses raw Material `Scaffold`/`AppBar` and raw `TextButton('SOS')` wrapping `ResidentReportScreen`, creating an awkward nested app-bar feel / inconsistent header height vs authenticated screens.
- **Proposed Layout Improvements:** Remove duplicate `Scaffold`/`AppBar` wrapper and delegate cleanly to `ResidentReportScreen(guest: true)` unified header (`pushedHeader` + high-visibility `"SOS"` action pill).
- **Navigation:** Pushed from `RoleSelectScreen`; pushes `SosScreen` or returns home on report completion.
- **Recommended Components:** Unified `ResidentReportScreen(guest: true)` with `AppHeader`.
- **Expected Improvements:** Seamless visual consistency between guest and registered reporting flows.
- **Priority:** `P2 Medium`

---

### Group C: Shared Operational & Utility Screens

#### 11. `AccountScreen` (`lib/screens/account_screen.dart`)
- **Current Purpose:** View/edit user profile (name, phone, email, avatar upload via `file_selector`), change password, view verification/approval state, request account deletion, and log out.
- **Existing Problems:** Currently **unreachable** from Resident & Responder apps; uses light-only `AppColors.dangerSurface`/`primarySurface`; edits fields by pushing raw `ApiEditScreen`; mixes `AlertDialog` and `confirmDialog`.
- **Proposed Layout Improvements:**
  - Clean profile summary header (`InitialsAvatar` / network photo with `"Change photo"` icon overlay, Name, Role badge, Registration status pill).
  - Grouped settings list with hairline dividers:
    - **Account Details** (`Name`, `Phone`, `Email`) -> inline clean edit bottom sheet or dedicated form with proper phone/email keyboards (no raw `ApiEditScreen` map dumps).
    - **Security** (`Change password`, opens proper password sheet).
    - **Session & Danger Zone** (`Log out`, `Request account deletion` with destructive `confirmDialog`).
- **Navigation:** Accessible in 1 tap from top-bar account/avatar icon or first row of `"More"` sheet in both `ResidentShell` and `ResponderShell`.
- **Recommended Components:** `AppScaffold`, `InitialsAvatar`, `AppSectionGroup`, `AppRowItem`, `AppButton`, `confirmDialog`.
- **Expected Improvements:** Restores full self-service account lifecycle to all live mobile users in clean iOS/M3-inspired grouped rows.
- **Priority:** `P0 Critical`

#### 12. `VoiceCallsScreen` & `VoiceCallsButton` (`lib/screens/voice_calls_screen.dart`)
- **Current Purpose:** Real-time Agora RTC audio console for resident SOS calls and responder dispatcher voice invitations.
- **Existing Problems:** Wraps controls in generic `Surface` boxes with wrapped `OutlinedButton.icon`s (looks like a settings form); uses Material `AlertDialog`, hardcoded `Colors.white`, and light-only `primarySurface`/`dangerSurface`/`warningSurface`; shows no live elapsed call timer; abruptly ends active calls when backgrounded without warning.
- **Proposed Layout Improvements:**
  - Top bar shows active call state pill (`Connected` / `Ringing` / `Waiting in queue`).
  - **Active Call Stage:** Crisp centered caller/dispatch header (`"MDRRMO Command Center"` / reporter name), live tabular call timer (`01:24`), subtle audio state subtitle, and a bottom-docked **3-button circular audio bar** (`56dp` Mute toggle, `56dp` Speaker toggle, `56dp` Red Hang-Up button).
  - **Queue / Incoming Invitations List:** Clean rows showing caller, report reference, wait duration, and clear `Join` / `Decline` buttons (when idle).
  - All confirmation prompts unified to `confirmDialog`; add a clear inline banner warning when backgrounding constraints apply.
- **Navigation:** Launched from top bar `VoiceCallsButton` (with live ringing/active badge) or `SosScreen` or `RecordDetailsScreen`.
- **Recommended Components:** `AppScaffold`, `AppBanner`, `AppCallControlBar`, `AppRowItem`, `confirmDialog`.
- **Expected Improvements:** Immediate call-screen mental model, safe large thumb controls, and dark-mode visual parity.
- **Priority:** `P1 High`

#### 13. `PendingSubmissionsScreen` (`lib/screens/pending_submissions_screen.dart`)
- **Current Purpose:** Displays locally stored idempotent submissions (`PendingSubmissions`) waiting confirmation after network timeouts/errors.
- **Existing Problems:** Hardcodes `AppColors.primarySurface` / `dangerSurface`; double `setState(() => _error = ...)` bug around `_load()` (lines 85–88); displays only `record.label` + `record.location` without timestamp or patient/purpose preview; no `"Discard"` action to clear broken/obsolete entries.
- **Proposed Layout Improvements:** Theme-safe top info banner explaining automatic duplicate protection; clean rows showing **Type**, **Submitted time**, **Location / summary**, and **Action bar** (`"Confirm & Sync"` primary + `"Discard"` destructive outline with `confirmDialog`). Header action `"Sync all"` when `>=2` items exist.
- **Navigation:** Accessed from `AppOfflineBanner` (`Queued (N)`), or `"More"` menu in both shells.
- **Recommended Components:** `AppScaffold`, `AppBanner`, `AppSectionGroup`, `AppButton`, `confirmDialog`.
- **Expected Improvements:** Eliminates stuck queue ambiguity and lets users safely purge unwanted failed drafts.
- **Priority:** `P2 Medium`

#### 14. `RouteNavigationScreen` (`lib/screens/route_navigation_screen.dart`)
- **Current Purpose:** Live GPS-to-incident / hospital OSRM routing, distance/ETA display, turn-by-turn directions, Photon address search, and dispatch status progression (`Start trip` -> `On scene` -> `Complete`).
- **Existing Problems:** Stacks 8 competing vertical sections inside one `Column`, crushing `FlutterMap` whenever hospital recommendations, search matches, or road directions expand; hides ETA & directions completely on `maxHeight < 480`; mixes raw `TextField`, `ListView`, `ExpansionTile`, and wrapped `TextButton`s.
- **Proposed Layout Improvements:**
  - **Full-Bleed `FlutterMap`** (`ResilientTiles`, polyline route, live GPS marker, destination pin, hospital pins).
  - **Floating Top Overlay (SafeArea):** Compact back pill + searchable destination bar (`"Search hospital or address..."`, tapping opens an inline/modal match list over the map without resizing the map).
  - **Floating Right Map Controls (`48x48dp`):** `Recenter GPS` (`AppIcons.locate`) + `Hospitals` filter pill (`AppIcons.hospital`).
  - **Bottom `DraggableScrollableSheet` (min `22%`, mid `45%`, max `85%`):**
    - Always visible at collapsed peek height: **Next Maneuver / Current Road**, **Tabular ETA + Distance** (e.g., `6 min · 2.4 km`), and **Primary Operational Action** (e.g., `Start trip` / `Mark on scene` / `Complete dispatch`).
    - Expanded view: **Turn-by-Turn Directions list** + **Recommended Hospitals switcher** (`distanceKm`, specialty badge, bed status, 1-tap `Route here`).
- **Navigation:** Pushed from Responder Home active assignment card, `ServiceScheduleCard`, or `RecordDetailsScreen`.
- **Recommended Components:** `FlutterMap`, `ResilientTiles`, `DraggableScrollableSheet`, `AppIconButton` (`48x48dp`), `AppButton`, `AppStatusBadge`.
- **Expected Improvements:** Solves map crushing across every screen size/orientation, preserves ETA & status progression on compact devices, and delivers genuine GPS-navigation ergonomics.
- **Priority:** `P0 Critical`

#### 15. `RecordDetailsScreen` (`lib/screens/record_details_screen.dart`)
- **Current Purpose:** Unified detail view for Incident Reports (Resident & Responder), Service Schedules, and Notifications; hosts status progression actions, map location preview, `TripSummary`, clinical `PatientCare` & `DriverForm` triggers, and voice call link.
- **Existing Problems:** Monolithic file (1,399 lines); places `"Voice call invitations"` button above `"Available actions"` even on resolved/closed records; mixes `AppButton` and plain `TextButton` for operational transitions; decorates every `DetailField` label with an icon (`Icons.*` visual clutter); uses light-only `primarySurface`/`dangerSurface`.
- **Proposed Layout Improvements:**
  - **Focused Top Summary Header:** Reference code (`RPT-104`), concise Incident/Service Title, clear Status + Priority badge pair, and reported timestamp (`tabularFigures`).
  - **Primary Action Dock (Context-Aware):** Shows active operational transition (`Start trip` / `Arrive on scene` / `Complete` / `Cancel schedule`) prominently; moves `"Voice call"` to an inline header/toolbar action or secondary strip only when relevant/active.
  - **Grouped Key-Value Sections (`DetailSection` refactored):** Clean 2-column or tight vertical label/value pairs without icon-beside-every-label noise (icons reserved strictly for section headers or interactive phone/map links like tappable phone call & coordinate preview).
  - **Clinical & Trip Logs Section (Responders):** Crisp rows for `Patient Care Report` and `Driver Trip & Fuel Form` showing completion status (`Saved` / `Needs entry`).
- **Navigation:** Pushed from Resident Home/History/Schedules/Updates, Responder Home/Services/History/Records, and Record Browser.
- **Recommended Components:** `AppScaffold`, `AppStatusBadge`, `AppSectionGroup`, `AppKeyValueRow`, `AppButton`.
- **Expected Improvements:** Immediately spotlights what action is next on a dispatch while cutting vertical scroll by ~30%.
- **Priority:** `P1 High`

#### 16. `ApiEditScreen` & `PatientCareScreen` (`lib/screens/record_details_screen.dart`)
- **Current Purpose:** Generic edit form (`ApiEditScreen`) backing Resident Report edits, Account details, Password Reset, and Clinical Patient Care Reports (`PatientCareScreen`).
- **Existing Problems:** Forces manual typing of ISO-8601 timestamps (`YYYY-MM-DDTHH:mm:ssZ`), `YYYY-MM-DD` dates, `HH:mm` times, and raw numeric `latitude`/`longitude` coordinates; `PatientCareScreen` mixes 17 clinical keys into one flat list (`patient.age`, `vitals.bp`, `assessment`, `hospital_endorsement`, etc.) without grouping.
- **Proposed Layout Improvements:**
  - Replace raw text `timestamp`/`date`/`time` fields with native **Read-Only Tap Pickers** (`showDatePicker` + `showTimePicker` + `"Set to now"` quick pill converting cleanly to required ISO/API string format internally).
  - Replace raw `latitude`/`longitude` inputs with a **Location Pin Preview Row** opening an interactive map pin picker (`"Adjust pin on map"`).
  - Refactor `PatientCareScreen` into its own file using structured `FormGroup`s: **Patient Baseline**, **Vital Signs** (compact 2-column grid for BP/HR/RR/Temp/SpO2 where width allows), **Clinical Assessment & Interventions**, and **Hospital Endorsement**.
- **Navigation:** Pushed modally/standard route from `RecordDetailsScreen` and `AccountScreen` (Password Reset removed from `ApiEditScreen` into dedicated `PasswordRecoveryScreen` flow).
- **Recommended Components:** `FormPage`, `FormGroup`, `AppDateTimeField`, `AppMapPinField`, `AppTextField`.
- **Expected Improvements:** Eliminates ISO-8601 syntax mistakes in the field and makes emergency clinical documentation vastly faster.
- **Priority:** `P1 High`

#### 17. `SearchScreen` & `RecordBrowserScreen` (`search_screen.dart`, `record_browser_screen.dart`)
- **Current Purpose:** Search and filter past Reports, Schedules, and Notifications/Records with date range and status filters.
- **Existing Problems:** `SearchScreen` wastes a full screen on 3 giant buttons; `RecordBrowserScreen` embeds search input, 2 date buttons, status dropdown, and Apply/Clear above results inside a scrolling list, pushing results off-screen; uses raw `TextField` and `DropdownButtonFormField`; hardcodes `AppColors.dangerSurface`.
- **Proposed Layout Improvements:** Merge `SearchScreen` into `RecordBrowserScreen` using a top `Segmented` control (`Reports` | `Schedules` | `Notifications`) + compact **Sticky Search Bar + Filter Button (`Filter (N)`)**. Opening Filters displays a bottom sheet with date presets (`Today`, `Last 7 days`, `Custom range`) + Status selector. Active filters appear as small removable outline chips right below the search bar.
- **Navigation:** Opens directly from `"More -> Search & Archive"` in either shell; row tap pushes `RecordDetailsScreen`.
- **Recommended Components:** `AppScaffold`, `Segmented`, `AppSearchBar`, `AppBottomSheet`, `AppRowItem`, `PageLoader`.
- **Expected Improvements:** Removes 1 extra screen transition and exposes results immediately on load.
- **Priority:** `P1 High`

---

### Group D: Resident Application Screens

#### 18. `ResidentShell` (`lib/screens/resident/resident_shell.dart`)
- **Current Purpose:** Main 4-tab navigation container (`Home`, `Reports`, `Services`, `Updates`), top header bar, SOS shortcut, `VoiceCallsButton`, and `"More options"` sheet.
- **Existing Problems:** Heavy solid `#1E40AF` `FHeader` dominates top chrome across every tab; `"More options"` omits `AccountScreen`; `state.isLoading` flashes a global `LinearProgressIndicator` on every 30s poll cycle.
- **Proposed Layout Improvements:**
  - Crisp neutral `AppHeader` (`#FFFFFF` light / `#111827` dark + `1px` bottom border) with subtle branding (`Balagtas MDRRMO`), `VoiceCallsButton`, compact red `SOS` pill (`48dp` tap area), and `Account / More` avatar or menu button.
  - Persistent `AppOfflineBanner` injected gracefully below header when offline.
  - Retain crisp 4-tab bottom `NavigationBar`: `Home`, `Reports`, `Services`, `Updates` (with semantic unread badge count on `Updates`) styled with Royal Blue `#4169E1` active indicator.
  - `"More & Account"` modal bottom sheet containing: **Account & Profile** (`AccountScreen`), **Search & Archive** (`RecordBrowserScreen`), **Pending Submissions** (`PendingSubmissionsScreen` with badge count), and **Log out**.
  - Background polling (`30s`) updates silently without flashing top progress indicator after initial load.
- **Navigation:** Root shell after resident auth.
- **Recommended Components:** `AppScaffold`, `AppHeader`, `NavigationBar`, `AppSheet`, `AppOfflineBanner`.
- **Expected Improvements:** Calmer header hierarchy making SOS unmistakably clear, restores Account access, stops 30s visual flicker.
- **Priority:** `P1 High`

#### 19. `ResidentHomeScreen` (`lib/screens/resident/home_screen.dart`)
- **Current Purpose:** Resident landing hub showing greeting, verification status, SOS call trigger, emergency reporting shortcut, service scheduling shortcut, and recent reports.
- **Existing Problems:** Duplicate branding (`"Balagtas Rescue"` header + `"BALAGTAS RESCUE"` pill above greeting); oversized 156x156 circular SOS button inside a large card duplicating header SOS; 3 stacked full-width shortcut cards pushing recent reports far down; unapproved account state dims `"Report an emergency"` without clear inline explanation on the card.
- **Proposed Layout Improvements:**
  - Concise top greeting row (`"Hello, <First Name>"` + Account link pill / Approval status banner if `registrationStatus != 'accepted'`).
  - **Primary Emergency Action Split (No 156x156 bloat):** Clean elevated action container featuring **Report Emergency** (Royal Blue primary CTA, clearly explaining approval requirement if pending) paired beside **Emergency SOS Call** (Semantic Red action CTA). Keep 1 clear in-page SOS trigger OR compact header SOS pill—never competing giant duplicates.
  - **Compact 2-Column Quick Actions Row:** `Request Service` + `Track Updates` (compact `AppTile`s).
  - **Recent Reports Section:** Clean grouped list of up to 3 latest reports using crisp status dots/labels and trailing chevrons (removing heavy card wrappers and repetitive `"View report ->"` text).
- **Navigation:** Switches tabs smoothly (`Reports`, `Services`, `Updates`) via shell callbacks instead of pushing redundant nested routes where tabs already exist.
- **Recommended Components:** `AppBanner`, `AppButton`, `AppSectionGroup`, `AppRowItem`, `AppStatusBadge`.
- **Expected Improvements:** Brings Recent Reports above/within first screenful, resolves unapproved state confusion, cuts scrolling by ~45%.
- **Priority:** `P0 Critical`

#### 20. `ResidentReportScreen` (`lib/screens/resident/report_screen.dart`)
- **Current Purpose:** 3-step emergency submission workflow (Who needs help? -> Incident & location details -> Confirmation reference), supporting both registered and guest users (`ReportScreen` / `GuestReportScreen`).
- **Existing Problems:** Step 1 advances on single card tap with no visual confirmation; Step 2 lacks `Form` key validation on submit (relying on bottom `snack(...)` for empty fields instead of inline red validation messages); no review summary; `PopScope` prompts discard from Step 2 instead of navigating back to Step 1; `ResidentFormStep` indicator supports only 2 steps despite 3 states.
- **Proposed Layout Improvements:**
  - Clean horizontal 2-step indicator (`1. Incident & Location` -> `2. Review & Send` or `1. Reporter` -> `2. Details`, plus clean final receipt state): allow tapping Step 1 row to highlight selection with `"Continue"` CTA OR make Step 1 a top compact **Segmented Toggle** (`For Myself` | `For Someone Else`) directly at the top of the report form! *Note:* Turning `"Who needs help?"` into a top `Segmented` toggle eliminates an entire forced step for registered residents in an emergency! (Keep `"Guest"` fields conditionally shown when `guest == true`).
  - Attach `GlobalKey<FormState>` so empty required fields highlight inline right away on submit, scrolling smoothly to the first invalid field.
  - Pre-attempt GPS pin on screen open with prominent `"Use Current GPS"` chip right above the map (`200dp` map preview + expand fullscreen modal button if precise adjustment needed).
- **Navigation:** In-tab flow or pushed route (`GuestReportScreen`); clean `PopScope` returns to prior step before prompting discard only when inputs are dirty.
- **Recommended Components:** `FormPage`, `Segmented`, `FormGroup`, `FlutterMap` + `"Use Current GPS"` chip, `AppTextField`, `AppSelect`.
- **Expected Improvements:** Cuts emergency reporting steps by 1 full screen for registered residents, guarantees inline field errors, prevents accidental lost input.
- **Priority:** `P1 High`

#### 21. `ScheduleScreen` (`lib/screens/resident/schedule_screen.dart`)
- **Current Purpose:** Resident portal to view scheduled municipal assistance requests (`My requests`) and submit new schedule requests (`New request`).
- **Existing Problems:** Uses inline `ChoiceChip`s inside a `ListView` to toggle completely different UIs; `_destination.addListener(() => setState(() {}))` triggers full-screen rebuilds on every typed character; renders redundant read-only `LockedField`s for user profile name/phone; `_PurposeChip` uses 6 distinct pastel/rainbow colors; status pills paint `'cancelled'`/`'declined'` as warning amber with raw lowercase API text (`pending`).
- **Proposed Layout Improvements:**
  - Top sticky `Segmented` control (`My requests` | `New request`).
  - **My Requests View:** Filterable clean grouped list (`All` / `Active` / `Past`), properly normalized status pills (`Pending`, `Confirmed`, `En Route`, `Completed`, `Declined`, `Cancelled`) with accurate semantic colors, swipe/tap-to-view details and `confirmDialog`-protected `"Cancel request"` action.
  - **New Request View:** Compact single-line summary banner showing who is requesting (`"For: <Name> · <Phone>"`), neutral selectable `Service Type` chips (Royal Blue selected state), clean native date + time slot pickers respecting Balagtas civil time validation (`input_validation.dart`), `ValueListenableBuilder`-scoped submit readiness (zero keystroke whole-page rebuilds).
- **Navigation:** Tab 3 in `ResidentShell`; item tap opens `RecordDetailsScreen(..., schedule: true)`.
- **Recommended Components:** `Segmented`, `FormPage`, `FormGroup`, `AppDateField`, `AppTimeField`, `AppChipGroup`, `AppRowItem`.
- **Expected Improvements:** Lag-free typing, accurate status comprehension, cleaner tab separation.
- **Priority:** `P2 Medium`

#### 22. `HistoryScreen` (`lib/screens/resident/history_screen.dart`)
- **Current Purpose:** Paginated history of all emergency reports submitted by the resident, filterable by `All reports` / `In progress`.
- **Existing Problems:** Uses nested `ResidentReportCard` boxes with repetitive `"View report ->"` footers; doesn't display brief incident symptoms/description or relative update time on list items; `_openOnly` filter operates only over already-fetched client pages without explaining unloaded history.
- **Proposed Layout Improvements:** Replace stacked cards with a clean `Segmented` filter bar (`All` | `In Progress`), compact grouped rows showing **Incident Type**, **Status Badge**, **Short Location**, and **Timestamp (`tabularFigures`) + trailing chevron**, plus `PageLoader` at bottom.
- **Navigation:** Tab 2 in `ResidentShell`; row tap opens `RecordDetailsScreen`.
- **Recommended Components:** `Segmented`, `AppSectionGroup`, `AppRowItem`, `AppStatusBadge`, `PageLoader`.
- **Expected Improvements:** Fits ~2x as many reports per viewport cleanly while showing higher-signal summaries.
- **Priority:** `P2 Medium`

#### 23. `NotificationsScreen` (`lib/screens/resident/notifications_screen.dart`)
- **Current Purpose:** Feed of status updates on resident reports and schedule requests, with `All` / `Unread` filter and `"Mark all read"`.
- **Existing Problems:** Inline `Wrap` combines filter chips and `"Mark all read"` unpredictably on narrow screens; repeats `"View details ->"` text on every single card alongside category pills.
- **Proposed Layout Improvements:** Clean top utility row (`All` | `Unread` segmented chips left, subtle `"Mark all read"` text/tonal action right). Render notifications as crisp grouped rows with a **Royal Blue 8dp unread indicator dot** on unread rows (tinted subtle brand surface only for unread state), concise bold title, 2-line preview, and relative timestamp (`timeAgo`).
- **Navigation:** Tab 4 in `ResidentShell`; tap marks read and navigates straight to associated `RecordDetailsScreen`.
- **Recommended Components:** `AppRowItem`, unread dot indicator, `PageLoader`, `AppEmptyState`.
- **Expected Improvements:** Instantly separates unread updates from read history without pill overload.
- **Priority:** `P2 Medium`

---

### Group E: Driver / Responder Application Screens

#### 24. Responder `Shell` (`lib/screens/driver-responder/shell.dart`)
- **Current Purpose:** Root 4-tab navigation shell for Drivers & Responders (`Dispatch`, `Service`, `Team`, `History`), header bar with `VoiceCallsButton`, notification inbox icon with unread badge, and `"More options"` sheet.
- **Existing Problems:** Heavy `#1E40AF` header bar; omits `AccountScreen` from header & `"More"` sheet; triggers `LinearProgressIndicator` on every 30s background poll; `LocationAccessGate` replaces only Tab 0 rather than cleanly indicating GPS status globally if tracking degrades.
- **Proposed Layout Improvements:**
  - Unified neutral `AppHeader` (`Balagtas MDRRMO` + subtle active role tag `Driver` or `Responder`), `VoiceCallsButton`, Inbox Bell with crisp badge count, and `Account / More` menu.
  - `"More & Dispatch Tools"` modal sheet featuring: **Account & Profile** (`AccountScreen`), **Driver Trip & Fuel Form** (`DriverFormScreen`), **Vehicle Maintenance** (`MaintenanceFormScreen`), **Report Emergency** (`EmergencyFormScreen`), **Reports I Submitted** (`ResponderRecordsScreen`), **Search Records** (`RecordBrowserScreen`), **Pending Sync** (`PendingSubmissionsScreen`), and **Log out**.
  - Silent 30s background updates without flashing progress bars.
- **Navigation:** Root shell after responder auth.
- **Recommended Components:** `AppScaffold`, `AppHeader`, `NavigationBar`, `AppSheet`, `AppOfflineBanner`.
- **Expected Improvements:** Unlocks missing Account access, puts key responder tools in predictable locations, removes 30s progress flicker.
- **Priority:** `P1 High`

#### 25. Responder `HomeScreen` & `HomeAssignmentsSection` (`home_screen.dart`, `home_assignments_section.dart`)
- **Current Purpose:** Dispatch command hub showing greeting + duty availability status, active emergency dispatches (`ResponderAssignmentCard`), active scheduled services (`ServiceScheduleCard`), live team/incident map preview (`_MapHero`), realtime connection diagnostics (`_ConnectionCard`), and quick tools (`Voice calls`, `Driver Form`, `Maintenance`, `Report emergency`).
- **Existing Problems:**
  1. Nested `DataRefresh` inside `HomeAssignmentsSection` creates a **duplicate 30s polling timer**.
  2. `_AssignmentActionTile` row uses `minimumSize: Size.zero`, `vertical: 8`, `fontSize: 11` (violating 48dp touch targets & type floor).
  3. Shows oversized `"YOUR RESPONSE DESK"` pill above greeting; mixes `StepperBar` (`10.5px` text, `22x22` circles) with `FilledButton` + 3 sub-48dp action tiles inside tall bordered cards.
  4. `_MapHero` shows `10px` driver labels and repeats map interaction underneath active cards.
  5. `_ConnectionCard` uses a raw `ExpansionTile` with dense technical sync details taking space on the main dispatch feed.
- **Proposed Layout Improvements:**
  - **Compact Duty Status Bar:** Driver/Responder name + current role (`Driver · Alpha Unit 1` / `Responder`) + **Availability Badge** (`Available` / `Dispatched` / `Off Duty`) + compact **Connection Indicator Dot** (tapping opens clean Connection Diagnostics modal sheet instead of cluttering Home!).
  - **Active Dispatch Card (Focal Priority #1):** High-contrast priority stripe (`Critical` red / `High` amber / `Normal` Royal Blue), concise Emergency Type + Reference, Destination & Patient summary, legible `3-step` progress bar (`>=12sp` labels, `24x24` circles), **1 clear Primary Progress Button** (`48dp` height: `Start trip` -> `Arrive on scene` -> `Complete dispatch`), and **2 spacious Secondary Action Buttons (`>=48dp` height)** (`Navigate`, `Details & Care`) instead of 3 cramped `11px` tiles!
  - **Active Scheduled Services** (`ServiceScheduleCard` refactored cleanly below).
  - **Compact `"Around You"` Live Map Preview (`180dp`)** with tap-to-expand option & `>=12sp` clean marker pills, plus compact **2x2 Quick Tools Grid** (`Voice Calls`, `Driver Form`, `Maintenance`, `Emergency Report`).
- **Navigation:** Dispatch actions push `RouteNavigationScreen`, `RecordDetailsScreen`, `DriverFormScreen`, `EmergencyFormScreen`, `MaintenanceFormScreen`, `VoiceCallsScreen`.
- **Recommended Components:** Single `DataRefresh` at `ResponderApp` only, `AppButton`, `AppRowGroup`, refactored `StepperBar`, `FlutterMap` + `ResilientTiles`.
- **Expected Improvements:** Eliminates duplicate timer drain, fixes critical touch-target violations inside ambulances, makes active dispatch steps unmistakable.
- **Priority:** `P0 Critical`

#### 26. `ServiceSchedulesScreen` & `ServiceScheduleCard` (`service_schedules_screen.dart`, `service_schedule_card.dart`)
- **Current Purpose:** Tab 2 in `ResponderShell` showing scheduled municipal transport/service requests assigned to the responder's team.
- **Existing Problems:** Every detail row inside `ServiceScheduleCard` uses colored icons beside every field; action footer uses small `TextButton.icon`s (`Details and progress`, `Navigate`); displays raw lowercase status strings (`confirmed`, `en-route`).
- **Proposed Layout Improvements:** Clean grouped cards with normalized status pills (`Confirmed`, `En Route`, `On Scene`, `Completed`), concise 3-line summary (`Service Type`, `Address`, `Date & Time · Resident`), and properly sized `48dp` action buttons (`Navigate` primary/tonal when active + `Details & Progress`).
- **Navigation:** Tab 2 in `ResponderShell`; opens `RouteNavigationScreen` or `RecordDetailsScreen(schedule: true)`.
- **Recommended Components:** `AppStatusBadge`, `AppKeyValueRow`, `AppButton` (compact `48dp` row), `PageLoader`.
- **Expected Improvements:** Cleaner visual density and reliable touch targets for schedule navigation.
- **Priority:** `P2 Medium`

#### 27. `TeamScreen` (`lib/screens/driver-responder/team_screen.dart`)
- **Current Purpose:** Displays user's team assignment, active role toggle (`SwitchListTile.adaptive` Driver vs Responder), assigned vehicle photo + selector (`DropdownButtonFormField`), maintenance status banner, `"Report maintenance"` button, and team member directory with tap-to-call.
- **Existing Problems:** Mixes Material `DropdownButtonFormField` with Forui surfaces; `"Report maintenance"` uses `OutlinedButton` while member calls use `IconButton.filledTonal`; vehicle placeholder + maintenance banner can push team roster far down on multi-team assignments.
- **Proposed Layout Improvements:**
  - **Role & Shift Section:** Clean role toggle row (`Driver Mode` switch) with clear single-line lock notice when locked by server.
  - **Assigned Vehicle Section:** Crisp compact horizontal header (`64x64` vehicle thumbnail + Unit Number + Maintenance status badge), `AppSelect` vehicle switcher (when multiple vehicles exist), and full-width `48dp` `"Report Vehicle Maintenance"` action button.
  - **Team Roster Section:** Grouped divider list showing `InitialsAvatar`, Member Name, Role tag, and `48x48dp` tap-to-call button (only when valid phone number exists).
- **Navigation:** Tab 3 in `ResponderShell`; launches `MaintenanceFormScreen` or `tel:` dialer.
- **Recommended Components:** `AppSelect`, `AppSwitchRow`, `InitialsAvatar`, `AppRowItem`, `AppButton`.
- **Expected Improvements:** Unified form controls, tighter vehicle header leaving room for roster above fold.
- **Priority:** `P2 Medium`

#### 28. Responder `HistoryScreen` & `DispatchDetailsScreen` (`history_screen.dart`, `dispatch_details_screen.dart`)
- **Current Purpose:** Date-grouped archive of completed/invalid dispatches (`All`, `Completed`, `Invalid` filter chips) and detail router (`DispatchDetailsScreen`).
- **Existing Problems:** `DispatchDetailsScreen` uses inconsistent error card if `recordId == null`; `_DispatchCard` repeats vehicle/reference badges cluttering multi-item days; filters use raw Material `ChoiceChip`s.
- **Proposed Layout Improvements:** Sticky top `Segmented` filter (`All` | `Completed` | `Invalid`), crisp `Date` section headers (`Today`, `Yesterday`, `fmtDay`), grouped rows per day showing **Emergency Type**, **Reference · Time (`tabularFigures`)**, **Destination**, and concise **Outcome Status Pill + Form Saved check** indicator (`Driver Form` indicator dot/tag).
- **Navigation:** Tab 4 in `ResponderShell`; opens `DispatchDetailsScreen` -> `RecordDetailsScreen`.
- **Recommended Components:** `Segmented`, `AppSectionGroup`, `AppRowItem`, `AppStatusBadge`, `PageLoader`.
- **Expected Improvements:** Instant visual verification of which completed trips still need a `DriverFormScreen` submission.
- **Priority:** `P2 Medium`

#### 29. `DriverFormScreen` & Removal of `StandaloneDriverFormScreen` (`driver_form_screen.dart`, `record_details_screen.dart`)
- **Current Purpose:** Trip Authorization & Fuel Consumption log (Government Trip Ticket parity with website reports).
- **Existing Problems:** Two completely separate implementations exist (`DriverFormScreen` vs `StandaloneDriverFormScreen` in `record_details_screen.dart`); computed fuel fields (`totalAvailableFuel`, `remainingFuel`) look like editable inputs; `Trip Date` uses editable text box + tiny outlined icon button; 13 stacked fields with no quick section jump or clear numeric grouping.
- **Proposed Layout Improvements:**
  - **Consolidate:** Delete `StandaloneDriverFormScreen` and route all entry points cleanly to `DriverFormScreen`.
  - **Dispatch Picker:** Clean top summary selector (`AppSelect`) with clear `"Saved"` / `"Pending"` indicator.
  - **Authorization Section:** Native tap-to-pick `Trip Date` field (`AppDateField`, `48dp`), auto-populated Driver / Vehicle / Authorized Passenger / Destination / Purpose `AppTextField`s.
  - **Fuel Consumption Section:** Input fields (`Balance in Tank`, `Issued by Office`, `Purchased During Trip`, `Fuel Used`, `Gear Oil Used`) arranged cleanly with decimal numeric keypad + `"L"` suffix, feeding a subtle sunken **Read-Only Calculated Summary Box** displaying `Total Available Fuel` and `Remaining Fuel` live in `tabularFigures` (preserving exact payload keys on submit!).
- **Navigation:** Pushed from Responder Home, Dispatch Actions, or `RecordDetailsScreen`.
- **Recommended Components:** `FormPage`, `FormGroup`, `AppSelect`, `AppDateField`, `AppTextField`, `AppCalculatedSummary`.
- **Expected Improvements:** Eliminates duplicate maintenance burden, prevents drivers accidentally overwriting computed fuel math, speeds up numeric input.
- **Priority:** `P1 High`

#### 30. `EmergencyFormScreen` (`lib/screens/driver-responder/emergency_form_screen.dart`)
- **Current Purpose:** Allows drivers/responders in the field to file a new emergency report on behalf of a citizen for dispatcher review.
- **Existing Problems:** Forces manual map tapping without a 1-tap `"Pin my current GPS"` button despite active GPS tracking; sets `confirmDialog(..., destructive: true)` making confirmation look like deleting data; displays server `_error` at the bottom below long scroll; mixes `AppIcons` with `Icons.check_circle`/`location_on`.
- **Proposed Layout Improvements:** Add a **1-tap `"Use my GPS"`** pill right above the map pin preview (plus center-target tap or fullscreen map modal); show server `_error` inside a persistent top `AppBanner` visible without scrolling down; change confirmation dialog to neutral Royal Blue primary confirmation (`destructive: false`); unify all icons to `AppIcons` (`FLucideIcons`).
- **Navigation:** Pushed from Responder Home Tools or More sheet; receipt state links to `RecordDetailsScreen` or returns Home.
- **Recommended Components:** `FormPage`, `FormGroup`, `AppSelect`, `AppTextField`, `FlutterMap`, `AppBanner`, `confirmDialog`.
- **Expected Improvements:** Dramatically faster roadside pinning and cleaner error visibility.
- **Priority:** `P1 High`

#### 31. `MaintenanceFormScreen` (`lib/screens/driver-responder/maintenance_form_screen.dart`)
- **Current Purpose:** Driver-only ambulance defect/maintenance report submission + past maintenance report status view.
- **Existing Problems:** Appends recent maintenance history directly below the submit form creating long pages; mixes Material `CheckboxListTile` with Forui `AppSelect`/`AppTextField`; silently catches offline history errors; shows top error text inline without banner styling.
- **Proposed Layout Improvements:** Use `Segmented` toggle or header `"Recent (N)"` sheet button to separate **Submit Report** from **Recent Reports** history; replace Material `CheckboxListTile` with unified `AppSwitchRow` (`Recommend out of service`); style offline notice clearly in the Recent view rather than swallowing errors silently.
- **Navigation:** Pushed from Team tab, Responder Home Tools, or More sheet.
- **Recommended Components:** `FormPage`, `FormGroup`, `AppSelect`, `AppTextField`, `AppSwitchRow`, `AppSheet`.
- **Expected Improvements:** Focused form layout and clear visibility into Admin review feedback (`admin_notes`).
- **Priority:** `P3 Low`

#### 32. `ResponderRecordsScreen` (`lib/screens/responder_records_screen.dart`)
- **Current Purpose:** Dual-mode archive screen: Responder Notification Inbox (`inbox: true`) and Reports Authored (`inbox: false`).
- **Existing Problems:** Stacks 2–3 badges (`RESPONSE UPDATE`, `Unread`, `Report #12`) + bullet dot + timestamp inside card headers; uses raw `ChoiceChip`s; mixes Material icons.
- **Proposed Layout Improvements:** Replace multi-pill headers with clean title row (Royal Blue unread dot + Bold Headline + right-aligned `tabularFigures` timestamp) and concise 1-line subtitle (`Report #12 · <Summary>`); convert `ChoiceChip` filter to crisp `Segmented` control (`All` | `Unread`).
- **Navigation:** Pushed via header Inbox bell (`inbox: true`) or More sheet (`inbox: false`); item tap opens `RecordDetailsScreen`.
- **Recommended Components:** `AppScaffold`, `Segmented`, `AppSectionGroup`, `AppRowItem`, `PageLoader`.
- **Expected Improvements:** Much calmer inbox readability for high-volume shift notifications.
- **Priority:** `P2 Medium`

---

### Group F: Legacy Module & Shared Dialogs / Bottom Sheets

#### 33. `OperationsApp`, `OperationsDetails` & `FleetMapScreen` (`operations_app.dart`, `fleet_map_screen.dart`)
- **Current Purpose:** Legacy mobile staff/admin/dispatcher interface (currently blocked from login via `AuthService._login()`).
- **Existing Problems:** 1,577 combined lines using outdated UI patterns (12 stacked full-width blue buttons, `SimpleDialog` menus, raw `entry.key: entry.value` text strings, light-only tint colors).
- **Proposed Recommendation:** Quarantine clearly under an internal/legacy label or remove from active mobile navigation paths if web dashboard handles all staff/admin workflows (confirm with product team before deletion due to `test/operations_screen_test.dart`). If kept testable, migrate hardcoded `AppColors.dangerSurface`/`primarySurface` to theme-aware tokens so analyzer/tests remain dark-mode clean.
- **Priority:** `P2 Medium`

#### 34. Cross-App Dialogs & Modal Bottom Sheets Inventory
| Modal / Sheet | Current Widget | Current Issue | Redesign Component |
| :--- | :--- | :--- | :--- |
| Confirmation prompts (Logout, Cancel Schedule, Submit Emergency) | Mix of `confirmDialog` (9x) and raw `AlertDialog` (20x) | Inconsistent button weights, heights, dark-mode backgrounds; `EmergencyFormScreen` marks submit `destructive: true` | **Unified `confirmDialog` (`FDialog` / themed M3 dialog)** with strict Primary/Destructive semantics (`destructive` ONLY for irreversible/delete actions) |
| `"More options"` Menus (`ResidentShell`, `ResponderShell`) | Custom `showModalBottomSheet` | Skips `AccountScreen`; inconsistent list tile sizing | **Unified `AppActionSheet`** with drag handle, grouped rows (`Account & Profile` first), `48dp+` row height, keyboard/safe-area inset compliance |
| Privacy Policy Modal (`RegisterScreen`) | `AlertDialog` | Cramped scrollable text box | **`AppContentSheet` (`DraggableScrollableSheet`)** with readable line height (`1.5`), clear close/accept CTA |
| Hospital & Directions Drawers (`RouteNavigationScreen`) | Inline `ExpansionTile`s | Crushes map viewport | **Native `DraggableScrollableSheet`** over full-bleed map |
| Record Search Filters (`RecordBrowserScreen`) | Inline expanded controls | Pushes results off screen | **`AppFilterSheet`** with date range presets + status multi-option selector |
| Active Call Exit / Permission Prompts | Material `AlertDialog` | Inconsistent styling & colors | **`confirmDialog` + `AppBanner`** |

---

## 4. Design System Specification

### 4.1 Brand & Color Philosophy
- **Primary Brand Accent (`#4169E1` Royal Blue):** Used intentionally for primary action buttons (`Sign in`, `Submit`, `Start trip`), active navigation indicators, selected segments/radios, links, and active input focus rings. It must NOT coat full-screen headers, secondary icons, or non-interactive badges.
- **Urgency Isolation (`#DC2626` Semantic Red):** Strictly reserved for **SOS Voice/Phone Emergency triggers**, critical priority flags, destructive delete/discard confirmations, and validation errors. Keeping Royal Blue neutral and Red rare makes emergency controls unmissable.
- **Subtle Borders over Shadows:** Zero multi-layered elevation drop shadows or glowing highlights. Depth is expressed cleanly via canvas-to-surface contrast (`#F8FAFC` vs `#FFFFFF`, `#0B1120` vs `#111827`) and crisp `1px` borders.

### 4.2 Complete Color Token System (`ThemeExtension<MdrrmoColors>`)

| Token | Light Mode Hex | Dark Mode Hex | Usage & Contrast Role |
| :--- | :--- | :--- | :--- |
| `canvas` | `#F8FAFC` | `#0B1120` | Scaffold background behind grouped sections |
| `surface` | `#FFFFFF` | `#111827` | Cards, grouped list backgrounds, top headers, bottom sheets |
| `surfaceSubtle` | `#F1F5F9` | `#1E293B` | Search inputs, secondary chips, sunken calculated summary boxes |
| `border` | `#E2E8F0` | `#263244` | `1px` hairline dividers, surface outlines, input borders |
| `borderStrong` | `#CBD5E1` | `#334155` | Focus-inactive strong outlines, segmented track border |
| `brand` | `#4169E1` | `#5B82F6` | Primary CTAs, active nav icon/label, focus ring (Dark mode lifted slightly for >=4.5:1 AA on `#111827`) |
| `brandPressed` | `#3154B6` | `#4169E1` | Pressed/hover primary state |
| `brandTint` | `#EEF2FF` | `#172554` (or `brand` @ 18% on `#111827`) | Selected row highlight, unread update surface, informational banner fill |
| `brandOn` | `#FFFFFF` | `#FFFFFF` | Text/icons placed on `brand` fills |
| `danger` | `#DC2626` | `#EF4444` | SOS action fill, critical priority, validation errors, destructive CTAs |
| `dangerTint` | `#FEF2F2` | `#450A0A` (or `danger` @ 18% on `#111827`) | Error banners, offline/warning alerts, maintenance out-of-service banner |
| `warning` | `#B45309` | `#F59E0B` | Pending/warning **text** (darkened to `#B45309` on light `#FFFBEB` for WCAG AA >=4.5:1!) |
| `warningTint` | `#FFFBEB` | `#451A03` | Pending verification, offline advisory, caution banners |
| `success` | `#15803D` | `#22C55E` | Available, Verified, Completed, GPS Ready |
| `successTint` | `#F0FDF4` | `#052E16` | Positive confirmation banners |
| `textPrimary` | `#0F172A` | `#F8FAFC` | Headlines, body values, primary labels |
| `textSecondary` | `#475569` | `#CBD5E1` | Subtitles, list previews, metadata labels |
| `textMuted` | `#64748B` | `#94A3B8` | Hints, timestamps, inactive tab icons (minimum 4.5:1 on `surface`) |

> **Accessibility Fix Note:** Existing `Semantic.warning` (`#D97706`) on white/`#FFFBEB` achieves only ~3.1:1 contrast for small text. Darkening light-mode warning text to `#B45309` achieves >5.0:1 WCAG AA compliance while preserving warm amber tone for icons.

### 4.3 Typography Scale (Replaces 21 Unscaled `fontSize` Literals)
Expose cleanly via `ThemeData.textTheme` & `MdrrmoTypography` helper, respecting `MediaQuery.textScaler` across `1.0x–2.0x`:

| Token | Role | Size / Line Height | Weight | Special Attributes |
| :--- | :--- | :--- | :--- | :--- |
| `displaySm` | Page greetings / Confirmation hero | `22sp / 28sp` | `w700` | Tracking `-0.3` |
| `titleLg` | Screen / Sheet headers | `18sp / 24sp` | `w700` | Tracking `-0.2` |
| `titleMd` | Section titles / Card headings | `16sp / 22sp` | `w600` | — |
| `bodyMd` | Primary body copy, input text, field values | `14sp / 20sp` | `w400` (`w500` emphasis) | — |
| `bodySm` | Secondary captions, timestamps, subtitles | `13sp / 18sp` | `w400` (`w500` labels) | `tabularFigures` on dates/times/coords |
| `labelSm` | Badges, compact pills, bottom nav labels | `12sp / 16sp` | `w600` | **Hard floor `12sp`** — eliminate `10/10.5/11/11.5px` |

- Enable `FontFeature.tabularFigures()` on call timers, ETAs, distance km, coordinates, reference IDs, odometer readings, and fuel liters so values never jitter horizontally while updating.

### 4.4 Spacing & Border Radius Tokens (4px / 8px Grid)
- **Spacing (`AppSpacing`):**
  - `xs = 4` (tight icon-to-text / badge inner vertical pad)
  - `sm = 8` (stack gap between compact related elements)
  - `md = 12` (gap between sibling form fields or compact sections)
  - `base = 16` (standard horizontal screen margin & card internal padding)
  - `lg = 24` (section separation & generous vertical breathing room)
  - `xl = 32` (major modal/onboarding separations)
- **Border Radius (`AppRadius`):**
  - `xs = 4` (small tags/status pills if square-ish, checkboxes)
  - `sm = 8` (buttons, text fields, segmented controls, compact map controls)
  - `md = 12` (grouped list containers, modal dialogs, cards)
  - `lg = 16` (top corners of `DraggableScrollableSheet` / bottom sheets ONLY)
  - `pill = 999` (avatars, unread dots, compact round chips — never oversized rectangular cards)

### 4.5 Component Standards (Forui + Material 3 Harmonized)
1. **Buttons (`AppButton`):** Always minimum **`48dp` height**, `AppRadius.sm` (`8dp`), zero custom `FontSize < 14sp`, built-in disabled & inline `16dp` spinner states while preserving label width. Variants:
   - `primary` (`brand` fill, `#FFFFFF` text)
   - `secondary` (`brandTint` fill, `brand` text — for helpful secondary tasks)
   - `outline` (`surface` fill, `1px borderStrong`, `textPrimary`)
   - `destructive` (`danger` fill ONLY for SOS or irreversible destructive confirmations)
   - `dangerOutline` (`1px danger` border, `danger` text — non-dominant emergency triggers)
2. **Inputs (`AppTextField`, `AppSelect`, `AppDateField`, `AppTimeField`):** Minimum `48dp` touch area, `1px border`, `1.5px brand` focus ring, `1.5px danger` error border, clear `13sp w600` label above field (never hiding required indicators), clear inline error below field (`12sp` min).
3. **Navigation Headers (`AppHeader`):** Standardized `56dp` toolbar height + `SafeArea` top, `surface` background with `1px` bottom `border`, crisp back button (`AppIcons.back`, `48x48dp`), concise title (`titleLg`), and max 2 trailing actions (`48x48dp`).
4. **Lists & Grouped Sections (`AppSectionGroup` + `AppRowItem`):** Prefer grouped `surface` containers with `1px` border and internal `1px border` hairlines between sibling rows over wrapping every item in its own card with `12dp` gaps. Interactive rows enforce `>= 52dp` height and trailing `AppIcons.chevronRight` instead of `"View details ->"` text.
5. **Status Indicators (`AppStatusBadge`):** Minimal semantic dot (`8dp` circle) + clear capitalized label inside a light tinted pill (`borderRadius: 6dp`, padding `8x4dp`, `12sp w600`). Maximum 2 badges per item (Status + Priority if emergency); eliminate decorative uppercase `"BALAGTAS RESCUE"` / `"YOUR RESPONSE DESK"` filler pills.
6. **Dialogs & Sheets (`confirmDialog`, `AppSheet`):** Unified theming from `MdrrmoColors`, explicit 1-line title, concise 2-line body, clear dual action bar (`Cancel` outline/text left, Confirm primary/destructive right, `>=48dp` buttons).
7. **Unified Lucide Iconography (`AppIcons`):** Map **all 219 `Icons.*` usages** cleanly onto `FLucideIcons.*` inside `AppIcons` (e.g., `shieldAlert`, `siren`/`phoneCall` for SOS, `navigation`, `ambulance`/`truck`, `wrench` for maintenance, `heartPulse` for patient care, `calendar`, `mapPin`, `crosshair` for locate, `hospital` / `building2`, `inbox`, `slidersHorizontal` for filters). Use icons strictly where they clarify navigation, state, or action—never beside every key-value label.
8. **Application States (`AppStateView`):** Consistent full/inline patterns for `loading` (clean skeleton/progress without layout jump), `empty` (muted 40dp Lucide icon + concise title + 1-line next step), `noSearchResults` (clear `"Reset filters"` CTA), `error` (`dangerTint` banner or retry state), `offline` (`AppOfflineBanner`), `permissionDenied` (`LocationAccessGate` checklist), and `success` (non-blocking snackbar / clean receipt page).

### 4.6 Accessibility & Ergonomics Checklist
- **Touch Targets:** Every interactive control (`IconButton`, `AppButton`, `Row`, `FilterChip`, map overlay button, step back arrow) meets **`>= 48x48dp`**.
- **Contrast:** Minimum **4.5:1** text contrast and **3.0:1** UI component border contrast across both Light and Dark themes.
- **Screen Reader Semantics:** Explicit `Semantics` labels on icon-only buttons (`SOS`, `Voice calls`, `Recenter GPS`, `More options`, `Call team member`) and live-region/badge count announcements (`"3 unread notifications"`).
- **Keyboard & Safe Area Discipline:** Respect `MediaQuery.viewInsets.bottom` in all forms and bottom sheets; use `TextInputAction.next`/`done` focus traversal across multi-field forms; wrap floating map controls in `SafeArea`.
- **Dynamic Text Scaling:** Verify zero `RenderFlex overflow` at `1.5x` and `2.0x` system font scale on `320dp` narrow screens (`Expanded`/`Flexible` labels, `Wrap` action bars when scaled).

---

## 5. Navigation and Workflow Improvements

### 5.1 Restructured Information Architecture

```text
App Launch (Auth Check, 0ms artificial delay)
 ├── Unauthenticated ──▶ RoleSelectScreen (SOS + Guest Report ALWAYS pinned & visible)
 │     ├── Guest SOS ──▶ SosScreen ──▶ VoiceCallsScreen / Cellular tel:
 │     ├── Guest Report ──▶ GuestReportScreen (2-step unified Emergency Report)
 │     └── Select Role ──▶ LoginScreen ──▶ RegisterScreen / PasswordRecoveryScreen
 │
 ├── Resident (ResidentShell — 4 Tabs + Account/More Sheet)
 │     ├── Header: [Title] [Voice Call] [SOS Pill] [Account/More]
 │     ├── Tab 1: Home (Status/Approval Banner · Report + SOS Split · Quick Actions · Recent Reports)
 │     ├── Tab 2: Reports (All / In Progress Segmented List -> RecordDetailsScreen)
 │     ├── Tab 3: Services (Segmented: My Requests | New Request -> RecordDetailsScreen)
 │     ├── Tab 4: Updates (All / Unread List + Mark All Read -> RecordDetailsScreen)
 │     └── Account/More Sheet: AccountScreen · RecordBrowserScreen · PendingSubmissionsScreen · Log out
 │
 └── Driver / Responder (ResponderShell — 4 Tabs + Account/More Sheet)
       ├── Header: [Title + Role] [Voice Call] [Inbox Bell Badge] [Account/More]
       ├── Tab 1: Dispatch (LocationAccessGate if off -> Availability & Connection Dot · Active Dispatches · Map Hero · 2x2 Quick Tools)
       │     ├── Dispatch Card -> RouteNavigationScreen (Full-Bleed Map + Draggable Sheet)
       │     └── Dispatch Card -> RecordDetailsScreen (Action Dock · Key-Values · PatientCareScreen · DriverFormScreen)
       ├── Tab 2: Service (Assigned Service Schedules -> RouteNavigation / RecordDetailsScreen)
       ├── Tab 3: Team (Role Switch · Vehicle + Maintenance Trigger · Team Roster w/ Dialer)
       ├── Tab 4: History (Date-grouped Dispatches w/ Form Completion Status -> DispatchDetailsScreen)
       └── Account/More Sheet: AccountScreen · DriverFormScreen · MaintenanceFormScreen · EmergencyFormScreen · Authored Reports · RecordBrowserScreen · PendingSubmissionsScreen · Log out
```

### 5.2 Key Friction Reductions
1. **Faster Cold Start to Emergency:** Removing the `2.4s` timer in `SplashScreen` + exposing `SOS` & `Guest Report` permanently on `RoleSelectScreen` cuts guest emergency time from ~5–6 seconds + 2 taps down to **<1 second + 1 tap**.
2. **Eliminating Unnecessary Navigation Hops:**
   - Folding `SearchScreen` directly into `RecordBrowserScreen` cuts **1 full push/pop cycle** per search.
   - Converting `ResidentReportScreen` Step 1 (`Who needs help?`) into a top `Segmented` toggle inside the report form cuts **1 full forced screen** during citizen emergencies.
   - Moving `RouteNavigationScreen` hospitals and directions into a **`DraggableScrollableSheet`** keeps the map, ETA, next turn, and `Start trip / On scene / Complete` controls visible simultaneously without opening/closing overlapping `ExpansionTile`s.
3. **1-Tap Account & Clinical Access:** Surfacing `AccountScreen` at the top of the More sheet (and/or profile button) solves a major missing-feature gap. Replacing raw `ApiEditScreen` coordinate/timestamp strings with native pickers removes manual syntax entry.
4. **Offline Resilience Without Disruption:** Turning `OfflineSosGate` from a destructive screen blocker into a persistent `AppOfflineBanner` with direct `SOS` & `Queued (N)` triggers keeps field workers productive in weak-signal zones while keeping offline SOS 1 tap away.

---

## 6. Flutter Architecture Recommendations

### 6.1 Theme & UI Consolidation (Non-Breaking)
- **Single Brightness-Aware Color Source:** Replace static light-only hex constants inside widgets with `MdrrmoColors.of(context)` (`ThemeExtension`) wired into both `AppTheme.buildMaterialTheme(Brightness.light)` and `AppTheme.buildMaterialTheme(Brightness.dark)`, plus matching `FThemeData` overrides so Forui and Material share identical background, surface, border, and primary colors.
- **Unify `lib/ui/` Kit & Retire Duplicate Role Kits:** Merge `ResidentWidgets` (`resident_widgets.dart`) and `ResponderWidgets` (`responder_widgets.dart`) into shared, composable primitives in `lib/ui/`:
  - `AppHeader`, `AppScaffold`, `AppOfflineBanner`
  - `AppSectionGroup`, `AppRowItem`, `AppStatusBadge`
  - `AppButton`, `AppTextField`, `AppPasswordField`, `AppSelect`, `AppDateTimeField`, `AppSearchBar`
  - `AppStateView` (handles loading, empty, error, permission gate consistently)
  - `AppSheet`, `confirmDialog`
- **Unified Lucide Icon Registry:** Expand `AppIcons` (`lib/ui/kit.dart` or split `lib/ui/app_icons.dart`) to cover all icon semantics needed across all 72 files using `FLucideIcons`, enforcing a lint/code-review rule against raw `Icons.*` in screens.

### 6.2 Targeted Structural & Bug Refactors
1. **Deduplicate `DriverFormScreen`:** Remove `StandaloneDriverFormScreen` from `record_details_screen.dart` and route every call site to the single `DriverFormScreen` with `initialReportId` / `initialAssignment` / `initialDispatch`.
2. **Break Up `record_details_screen.dart` (1,399 lines):** Split cleanly into:
   - `record_details_screen.dart` (details presentation & actions)
   - `api_edit_screen.dart` (typed field editing with native date/time/map-pin controls)
   - `patient_care_screen.dart` (clinically grouped Patient Care form)
3. **Fix Nested `DataRefresh` Timer:** Remove `DataRefresh` from `HomeAssignmentsSection` (`home_assignments_section.dart`) so only `ResponderApp` manages the single 30-second periodic lifecycle timer.
4. **Distinguish `isInitialLoading` vs `isRefreshing`:** Update `ResidentState` and `ResponderState` (or view flags) so background 30s polls refresh state seamlessly without flashing shell-wide `LinearProgressIndicator`s.
5. **Fix `ScheduleScreen` Per-Keystroke Rebuild:** Replace `_destination.addListener(() => setState(() {}))` with `ValueListenableBuilder<TextEditingValue>` around the submit validation readiness check.
6. **Fix `PendingSubmissionsScreen` Error Bug & Support Discard:** Remove the duplicate `setState(() => _error = ...)` sequence around `_load()` (lines 85–88) and expose `PendingSubmissions.remove(...)` cleanly behind a `confirmDialog`.
7. **Responsive Frame Utility (`ContentFrame`):** Wrap scrollable bodies and modal sheets in `Center(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: 640), ...))` so tablets, foldables, and landscape orientations stay legible instead of stretching form lines edge-to-edge.
8. **Quarantine Dead `OperationsApp` Code:** Move/document `operations_app.dart` + `fleet_map_screen.dart` clearly as legacy/test-only unless stakeholder review confirms removal, ensuring zero impact on mobile login rules while keeping `test/operations_screen_test.dart` passing.

### 6.3 Strict Preservation Guarantees
All UI/UX changes MUST preserve 100% of existing:
- API routes, query params, and JSON payload schemas (`DriverApi`, `ResidentApi`, `GuestReportApi`, `AuthService`, `VoiceCallsApi`, `GuestVoiceCallsApi`)
- Idempotent submission keys & storage format (`PendingSubmissions` `Idempotency-Key`)
- WebSocket channels & event handlers (`DriverRealtime` `private-drivers.{id}`, `driver.moved`, `report.updated`, `team.role.updated`)
- Background GPS session lifecycle (`DriverTracking`, `AutomaticDriverTracking`)
- Civil-time Balagtas (UTC+8) & Philippine mobile number validations (`InputValidation`)
- `AppPrefs` persistence keys (`Resident` / `Responder`)

---

## 7. Implementation Roadmap

Execute incrementally across **7 gated phases**, verifying `flutter analyze` and existing/new tests after each phase:

- **Phase A — Design System, Theme Extensions & Core Primitives**
  - Implement `MdrrmoColors`, `MdrrmoTypography`, `AppSpacing`, and `AppRadius` in `lib/ui/app_theme.dart` for both light and dark modes (fixing `_royalBlueLight` background/surface inversion and contrast ratios).
  - Expand `AppIcons` with full `FLucideIcons` coverage; standardize `AppButton`, `AppTextField`, `AppPasswordField`, `AppSelect`, `AppDateTimeField`, `AppSectionGroup`, `AppRowItem`, `AppStatusBadge`, `AppBanner`, `AppSheet`, `confirmDialog`, and `ContentFrame`.
  - Retire duplicated `ResidentWidgets` / `ResponderWidgets` wrappers cleanly.

- **Phase B — App Bootstrap, Navigation Shells & Account Integration**
  - Update `AppStartup` (dark-aware error card) and `SplashScreen` (remove `2.4s` artificial delay).
  - Refactor `OfflineSosGate` into non-blocking `AppOfflineBanner` + on-demand `SosScreen`.
  - Refactor `ResidentShell` & Responder `Shell` (unified neutral `AppHeader`, consistent `NavigationBar`, `"Account & More"` sheet surfacing `AccountScreen`, silent background refreshes).

- **Phase C — Core Operational Screens**
  - Redesign `ResidentHomeScreen` (remove double branding & oversized SOS card, refine quick actions & grouped recent reports).
  - Redesign `ResidentReportScreen` (top `Segmented` reporter toggle, `Form` inline validation, GPS helper, clean step-back handling).
  - Redesign Responder `HomeScreen` & `HomeAssignmentsSection` (remove nested `DataRefresh`, fix `<48dp` `_AssignmentActionTile`, clean dispatch card & compact connection modal).
  - Redesign `RouteNavigationScreen` (full-bleed `FlutterMap` + floating search/controls + `DraggableScrollableSheet` for ETA, turns, and recommended hospitals).

- **Phase D — Secondary Screens, Dialogs, Forms & Bottom Sheets**
  - Redesign `RoleSelectScreen` (pinned guest emergency bar), `LoginScreen` (compact header + proper back stack), `RegisterScreen` (`AppSheet` privacy modal), `PasswordRecoveryScreen` (unified 2-stage flow).
  - Redesign `AccountScreen` (self-service grouped profile & security controls).
  - Redesign `VoiceCallsScreen` (dedicated call stage + elapsed timer + docked `56dp` circular controls + `confirmDialog`).
  - Merge `SearchScreen` into `RecordBrowserScreen` (top tabs + filter modal sheet).
  - Redesign `ScheduleScreen` (segmented split, `ValueListenableBuilder`, normalized statuses), Resident `HistoryScreen`, `NotificationsScreen`, `ServiceSchedulesScreen`, `TeamScreen`, Responder `HistoryScreen`, and `ResponderRecordsScreen`.
  - Split `record_details_screen.dart`: redesign `RecordDetailsScreen`, upgrade `ApiEditScreen` (native pickers/map pin), group `PatientCareScreen`, delete duplicate `StandaloneDriverFormScreen`, polish `DriverFormScreen` (read-only calculated fuel box), `EmergencyFormScreen` (`Use my GPS` + top error banner + neutral confirmation), and `MaintenanceFormScreen`.

- **Phase E — Application States & Error Recovery**
  - Standardize `AppStateView` across every async view (loading, empty, no-search-results, network error, permission denied, success receipt).
  - Refactor `LocationAccessGate` (2-step readiness checklist) and `PendingSubmissionsScreen` (timestamps, payload summary, `"Discard"` action, fixed `_error` state handling).
  - Audit all `ResilientTiles` map error states for dark mode consistency.

- **Phase F — Accessibility, Touch Targets & Responsive Layout Audit**
  - Audit every tap target (`>= 48x48dp`) including notification rows, map buttons, date pickers, and team call icons.
  - Sweep and eliminate all remaining `Icons.*`, hardcoded `Color(0x...)`, light-only `*Surface` references, and `<12sp` font literals.
  - Verify `ContentFrame` (640dp max width) across tablet/landscape viewports and zero overflow at `1.5x`–`2.0x` `textScaler` on `320dp` width.

- **Phase G — Testing, Bug Fixes & Final Polish**
  - Update existing 25 test files where widget finders depend on legacy button text/types (without weakening assertions!).
  - Add widget & golden/theme tests covering Dark Mode, dynamic text scaling (`2.0x`), `RouteNavigationScreen` compact viewport behavior, `AccountScreen` reachability, and `PendingSubmissionsScreen` error/discard flows.
  - Run full `flutter analyze` and `flutter test` suite until 100% green.

---

## 8. Risk Assessment

| Risk Area | Impact | Likelihood | Mitigation Strategy |
| :--- | :--- | :--- | :--- |
| **Breaking existing widget tests** (25 test files in `test/`, e.g., `resident_ui_test.dart`, `responder_ui_test.dart`, `route_navigation_test.dart`, `sos_call_test.dart`, `operations_screen_test.dart`) | High | High | Inspect exact test finders (`find.text`, `find.byIcon`, widget types) during Phase B–D edits; preserve semantic labels and clean test-friendly copy; update UI-dependent tests cleanly in Phase G. |
| **API payload drift on form refactors** (`DriverFormScreen`, `PatientCareScreen` dot-prefixed keys, `ApiEditScreen` ISO timestamps, `EmergencyFormScreen`) | Critical | Medium | Keep controller serialization and `DriverApi`/`ResidentApi`/`GuestReportApi` payload keys untouched; validate formatted ISO-8601 output from native date/time pickers via unit tests. |
| **Idempotency queue mismatch** (`PendingSubmissions` key/payload comparison) | High | Low | Do not alter `PendingSubmissions` storage schema or endpoint keys; expose discard purely via new safe helper with explicit confirmation. |
| **Live GPS / Realtime / Voice lifecycle regressions** (`AutomaticDriverTracking`, `DriverRealtime`, `VoiceCallController`) | Critical | Medium | Preserve stateful ownership inside `ResponderApp` / `ResidentApp`; removing only the duplicate `DataRefresh` inside `HomeAssignmentsSection` must not affect WebSocket or GPS listeners. |
| **Forui `0.27.7` vs Material 3 styling conflicts** (e.g., `FDialog` vs `DraggableScrollableSheet`, keyboard insets inside `FScaffold`) | Medium | Medium | Test `FScaffold` + `ModalBottomSheet` keyboard resizing explicitly on small Android viewports; use Material M3 sheets/controls wrapped in `MdrrmoColors` where Forui lacks a native equivalent (like `DraggableScrollableSheet` or `NavigationBar`). |
| **Unintended impact from `OperationsApp` archival** | Low | Low | Confirm stakeholder intent before deleting `operations_app.dart`; initially only fix light-only surface leaks unless approved for removal. |

---

## 9. Acceptance Criteria

Implementation will be considered complete only when all criteria below are verified:
1. **Zero Light/Dark Contrast Failures:** All 18 hardcoded light-surface/border references (`surfaceLight`, `borderLight`, `primarySurface`, `dangerSurface`, `warningSurface`) outside theme configuration are eliminated; every screen renders cleanly in both Light (`#F8FAFC`/`#FFFFFF`) and Dark (`#0B1120`/`#111827`) modes.
2. **Design Token Consistency:** `0` raw `fontSize` literals below `12sp`; inline `TextStyle(` calls reduced to explicit intentional exceptions (`MdrrmoTypography` used everywhere else); `0` hardcoded `Color(0x...)` outside `app_theme.dart`.
3. **100% Icon & Dialog Parity:** All 219 `Icons.*` calls migrated to `AppIcons` (`FLucideIcons`); all dialogs unified under `confirmDialog` / `AppSheet`; all text inputs unified under `AppTextField` / `AppSelect` / native pickers.
4. **Account & SOS Accessibility:** `AccountScreen` is reachable within 1–2 taps in both `ResidentShell` and `ResponderShell`; Guest `SOS` and `Guest Report` are visibly reachable on `RoleSelectScreen` without selecting a role first.
5. **Map & Compact Viewport Usability:** `RouteNavigationScreen` keeps `>= 60%` interactive map visibility even with hospital/directions sheets open, and displays ETA + next maneuver + dispatch CTA even at `maxHeight < 480dp`.
6. **Touch & Scale Accessibility:** All interactive controls measure `>= 48x48dp`; zero layout overflow warnings across `320dp` phone width at `1.5x` and `2.0x` `textScaler`, and clean centered max-width framing (`640dp`) on tablet widths.
7. **Single Polling Loop & Clean Cold Start:** Zero artificial `2.4s` timer in `SplashScreen`; zero duplicate `DataRefresh` timers on Responder Home; zero 30s background progress-bar flicker.
8. **Verification Gate:** `flutter analyze` exits `0` with zero issues, and all existing + redesigned widget/unit tests pass completely without skipped or weakened assertions.

---

## 10. Final Recommendations

Before writing any implementation code in **Phase A**, confirm these three lightweight product/architectural alignment decisions:
1. **Top App Bar Neutrality (`#FFFFFF` / `#111827`) vs Solid Header Blue (`#1E40AF`):** Adopting clean neutral top app bars with a hairline bottom divider lets Royal Blue (`#4169E1`) focus strictly on interactive CTAs/tabs and makes the Semantic Red (`#DC2626`) SOS trigger stand out sharply without heavy blue blocks dominating every screen. Confirm if you prefer this clean neutral header or want to keep solid blue headers on certain screens.
2. **Disposition of Legacy `OperationsApp` & `FleetMapScreen`:** Since `AuthService._login()` blocks `admin`/`dispatcher` logins on mobile, confirm whether `operations_app.dart`, `fleet_map_screen.dart`, and `operations_screen_test.dart` should be removed entirely during cleanup or retained as light/dark-fixed legacy test code.
3. **Account Profile Edit Scope:** Confirm whether residents/responders editing fields inside `AccountScreen` should retain partial edits (Name/Phone/Photo) as currently supported by the backend API, so we design the exact inline edit sheet cleanly around supported API fields.

Once this plan is approved, implementation will proceed sequentially from **Phase A through Phase G**, starting with `lib/ui/app_theme.dart` and `lib/ui/kit.dart` before updating shells and individual screens.
