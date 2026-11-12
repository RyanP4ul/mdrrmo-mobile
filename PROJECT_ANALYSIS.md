# Flutter Project Analysis

> **Live-map incident fixed and verified, 2026-11-04:** The live PostgreSQL connection inherited `Asia/Kuala_Lumpur` (UTC+8), while Laravel creates dates in UTC. Offset-free timestamp bindings made newly created tracking leases appear eight hours expired, producing repeated session restarts and zero accepted positions despite a connected mobile WebSocket. `config/database.php` now explicitly sets the PostgreSQL connection timezone to UTC, and the configuration cache was cleared. A read-only PostgreSQL timestamp probe confirms a new three-minute lease remains approximately 180 seconds in the future. The actual phone then created a healthy session and persisted its GPS readings. An isolated, authenticated local subscription to the real private `dispatch` Reverb channel received a live `driver.moved` event from that phone; the dispatcher query returns its active saved position. This verifies foreground mobile-to-dispatch transport; sustained background delivery remains unverified. The web map now frames the initial driver positions and focuses a selected driver instead of keeping all positions outside the fixed default viewport. Nine affected backend tests passed (93 assertions).

> **Current implementation - driver/responder tracking and vehicle-management removal, 2026-11-04:** Driver and responder are the same `driver/responder` account role. The current website/mobile operational interfaces no longer manage vehicles. The mobile Vehicles list/editor, vehicle fields in the driver details form, vehicle history/detail labels, and Home's entire **My status** card have been removed. The dispatcher map lists driver/responder names. Dispatch and automatic dispatch select active linked driver/responder accounts, including roster members labelled Responder, without an available-vehicle requirement. Response progress is persisted per report in `dispatch_trips` rather than requiring a vehicle. Existing historical vehicle records and legacy compatibility endpoints are retained; no historical records were deleted.
>
> **Current coordinate flow:** `ResponderApp` owns `AutomaticDriverTracking` and `DriverTracking`. Once the authenticated responder bootstrap has loaded and `LocationAccessGate` confirms OS access, automatic sending starts even without an assignment or vehicle. The client opens `POST /driver-responder/location/sessions` with `background` and `notice_version: driver-2026-11-04`; driver identity comes from the authenticated account. GPS fixes upload approximately every ten seconds to `/driver-responder/location/sessions/{id}/ping`. The API validates token ownership, coordinates, accuracy, observation time and sequence; persists the latest reading in `driver_locations`; then broadcasts **driver.moved** through `DriverLocationUpdated` to the private dispatcher and authorized teammate channels. The dispatcher `DriverMap` updates the marker directly from that event. Initial/reconnect snapshots use the same driver identity and DTO; stale events cannot overwrite newer ones. Location leases expire after three minutes without accepted updates, and the map marks expired locations offline. Location access loss, sign-out/session expiry and disposal stop local sending; supported Android/iOS devices use the existing background service/indicator. Dispatch completion does not stop driver location sharing while the user remains signed in with access enabled.
>
> **Files and database:** `lib/services/driver_tracking.dart`, `automatic_driver_tracking.dart`, `driver_realtime.dart`, responder Home/shell/profile/history, location gate and staff screens; `app/Models/DriverLocation.php`, `app/Events/DriverLocationUpdated.php`, `app/Http/Controllers/MobileDriverLocationController.php`, `app/Services/DriverResponseProgress.php`, dispatcher map/controller and `resources/js/lib/live-drivers.ts`. The additive `2026_11_04_044040_create_driver_location_tracking_tables.php` migration creates `driver_location_sessions`, `driver_locations`, and the optional `dispatch_trips.returning_at` column; it has been applied to local PostgreSQL. Mobile driver map snapshots use `GET /driver-responder/locations`; staff mobile snapshots use `GET /operations/locations`. The three mobile vehicle CRUD routes were removed; profile requests cannot edit vehicle fields.
>
> **Verification:** All **78 Flutter tests**, **111 backend tests / 783 assertions**, and **3 driver-map Node tests** passed. Dart analysis and TypeScript checking are clean; the website build passed. The final bootstrap/logout adjustments also passed 38 targeted backend tests. Actual physical-phone background delivery is still unverified, and the previously diagnosed phone-to-Reverb port 8080 timeout requires the host firewall/network fix. GPS uploads use the reachable Laravel API independently of the phone's WebSocket connection; server-side Reverb distributes accepted readings to the dispatcher website. The older vehicle-sharing notes below describe superseded behavior.

> **Current behavior update - automatic responder coordinates, 2026-11-04:** The manual Vehicle location sharing page, menu entry, consent checkbox and Start/Stop sharing buttons have been removed. `AutomaticVehicleTracking` starts sending coordinates once location access is ready and the selected assignment is dispatched with an assigned vehicle. It switches sessions when the assignment/vehicle changes and stops on assignment removal/completion, access loss, sign-out/session expiry or disposal. Android/iOS use the existing native background mode with visible platform indicators; other targets stop on app pause and recheck access on return. OS restrictions still apply; physical-device background delivery is unverified. Failures retry after 30 seconds and Home displays the sending/error status.
>
> The session API accepts `sharing_mode: automatic`, `report_id` and `notice_version: 2026-11-04`, verifies the current assigned dispatch, and stores `automatic:2026-11-04` in the existing legacy `consent_version` audit column. Automatic mode does not claim a manual checkbox consent. Older manual clients remain compatible. Existing authorization, coordinate validation, database writes and Reverb broadcasts remain in use. No schema migration is required. The previously diagnosed phone-to-Reverb port 8080 timeout still needs the host firewall/network fix; automatic uploads use the API and do not resolve that socket reachability issue.

> **Automatic-coordinate verification:** All **78 Flutter tests** pass and Dart analysis is clean. The **36 targeted backend tests** covering optional features, Reverb, records and tracking pass (**286 assertions**). Native background delivery on the physical phone remains unverified.

> **Current implementation update - Reverb live maps and mobile location gate, 2026-11-04:** Dispatcher web and driver/responder mobile maps now receive authenticated Laravel Reverb updates. Flutter uses `web_socket_channel ^3.0.3`; `app_settings ^9.0.1` opens native location/app settings. This section supersedes earlier polling-only notes for these two maps. Admin/operations mobile fleet maps retain their existing polling behavior.
>
> **Verified:** Dart analysis is clean; **70 Flutter tests**, **105 backend tests / 704 assertions**, and **3 Node map-event tests** pass. TypeScript checking and Vite production build pass. A local Reverb server was started on port **8080**; an actual WebSocket handshake, HMAC-authorized private subscription and isolated coordinate-event delivery passed. No business records were created by that transport check. Physical-phone/background behavior, Windows native plugin linking, deployment/network verification and release signing remain unverified/deferred as previously recorded.

### Live coordinate flow

1. A responder opens Home. `LocationAccessGate` checks location services and permission before showing the map. Disabled/denied access displays Enable location, settings and retry actions; permanently denied permission opens app settings. Access is rechecked every three seconds in the foreground and on app resume. Turning location off hides the map and stops sharing. Device location appears as a separate marker once a recent accurate fix is available.
2. `AutomaticVehicleTracking`, owned by `ResponderApp`, starts a session for the selected active assignment and its assigned vehicle once `LocationAccessGate` confirms access. Home shows automatic sending status. There is no separate sharing page or Start/Stop action.
3. `VehicleTracking` sends coordinates through the authenticated, validated tracking API. `MobileLocationController` persists the accepted fix in the website's existing vehicle record and dispatches `VehicleLocationUpdated` after commit. Sequence/observation ordering, accuracy, assignment ownership, token binding and tracking leases remain enforced. Coordinates are uploaded through the API; Reverb carries the server-authorized live updates to map subscribers.
4. The dispatcher website subscribes to private `dispatch` using Laravel Echo/Reverb. Each `vehicle.moved` message updates or creates the vehicle marker directly, including speed/status/observation time, without a page reload for each GPS fix. `report.updated`, reconnects and first-seen vehicles trigger coalesced authoritative refreshes. Older messages cannot replace newer coordinates. A 15-second fallback refresh remains available when the subscription is disconnected.
5. The mobile `DriverRealtime` client obtains public connection settings from Laravel, authenticates its socket through the bearer-protected API and subscribes to private `drivers.{id}`. It handles Pusher/Reverb subscribe frames, ping/pong, timeout, exponential reconnect, foreground resume and disposal. Live vehicle markers are restricted to the responder's active teams; report updates refresh assignments. Reconnect/foreground snapshots fill missed updates, with timestamp guards protecting newer frames.

### Authorization, configuration and files

- `GET /api/driver-responder/realtime` returns only public Reverb key/host/port/scheme and the signed-in driver's private channel. It never returns the Reverb secret. The public host defaults to the API request hostname so an emulator or phone does not incorrectly connect to its own localhost. Optional `MOBILE_REVERB_HOST` supports a separate public WebSocket host.
- `POST /api/driver-responder/broadcasting/auth` validates the socket ID and authorizes only `private-drivers.{current_user_id}` using Sanctum and the driver-read ability. Driver tokens cannot authorize the dispatcher channel or another driver. The existing browser `/broadcasting/auth` continues to authorize the dispatcher session.
- `GET /api/driver-responder/fleet` returns the active team's vehicles only. `VehicleLocationUpdated` broadcasts to the dispatcher plus active linked team members' private driver channels. `EmergencyReportUpdated` notifies the assigned driver and, on reassignment, the previous driver so their stale assignment can be removed. No patient-care fields are broadcast in these map events.
- Backend: `mdrrmo/app/Http/Controllers/MobileRealtimeController.php`, `app/Events/VehicleLocationUpdated.php`, `app/Events/EmergencyReportUpdated.php`, `app/Services/DispatchService.php`, `app/Http/Controllers/Dispatcher/MapController.php`, `routes/api.php`, `routes/channels.php`, `config/mobile.php`.
- Website: `mdrrmo/resources/js/Pages/Dispatcher/Map.tsx`, `resources/js/lib/live-fleet.ts`, `resources/js/components/maps/FleetMap.tsx`, `resources/js/app.tsx`. Live subscription status is visible; full snapshots and event timestamps are reconciled to avoid stale responses moving markers backwards.
- Flutter: `lib/services/driver_realtime.dart` (`DriverRealtime`, `ReverbSocket`, `ChannelReverbSocket`), `lib/screens/location_access_gate.dart` (`LocationAccessGate`, `MapLocationScope`), responder module/shell/Home integration, `pubspec.yaml` and lockfile. Initial map fitting/recenter includes the device and assigned incident when available.
- Tests: `mdrrmo/tests/Feature/MobileRealtimeTest.php`, `tests/Frontend/live-fleet.test.mjs`, `test/driver_realtime_test.dart`, `test/location_access_gate_test.dart`, plus all earlier regression suites. Tests cover private auth/scoping, saved GPS event payloads, marker insertion/update/order, socket handshake/recovery/disposal, permanently denied permission and location being disabled after map access.

### Running and remaining verification

The existing local backend already had Reverb credentials and `BROADCAST_CONNECTION=reverb`; no server secrets were copied to Flutter or changed. The local server was started with `php artisan reverb:start --host=0.0.0.0 --port=8080`. Keep Reverb running alongside Laravel and the website. Physical devices must reach the API and WebSocket host/port over the network; public HTTPS/WSS/proxy/firewall configuration remains part of the deferred deployment phase. Existing Windows Developer Mode/symlink support is still required to finish native Flutter plugin linking. Native permission dialogs, GPS delivery and background service behavior still require a physical-device run. The operating system and user control location access; the app provides the enable/settings flow and blocks the map until access is granted.

---


> **Previous implementation update - optional features 16, 21, 23, 25 and 26, 2026-11-03:** The five requested features are implemented in Flutter and the shared Laravel backend. The user selected a **staff-controlled automatic-dispatch switch**, so it is **off by default** and was not enabled on the local database. This section supersedes the historical audit and previous batch notes below. Deployment verification and release signing remain deferred.
>
> **Verification:** Dart analysis reports no issues; **66 Flutter tests** and **101 backend tests / 677 assertions** pass. Backend tests use isolated in-memory SQLite. The new migration `mdrrmo/database/migrations/2026_11_03_120057_add_mobile_operations_and_tracking.php` was applied successfully to local PostgreSQL as batch 9. Only this new migration was applied; the unrelated website index migration remains pending. Native manifest/plist/entitlement XML was parsed successfully.
>
> **Limits:** no physical-device GPS/background-service test, signed build, store submission, deployment verification or operating-system configuration was performed. `location ^10.0.2` resolved/downloaded successfully, but Windows native plugin linking still reports the previously documented Developer Mode/symlink prerequisite. Background tracking is implemented for Android/iOS during an explicitly started sharing session; OS restrictions or force-closing the app can stop updates. It does not promise tracking after force-stop or automatic restart. Scheduled dispatch retries require Laravel's scheduler to be running; scheduler hosting was not configured in this deferred deployment phase.

### Requested optional-feature implementation status

| Requested item | Implemented behavior | Principal files |
|---|---|---|
| **16 - GPS permissions, location updates, background tracking** | Coordinates send automatically for the selected active vehicle dispatch after OS location access is available. Android/iOS use native background mode and visible platform indicators; other targets send in the foreground. Home shows sending/error status. Assignment changes close the old session; completion, location-access loss and sign-out stop sending. Failures retry after 30 seconds; pending starts are invalidated when their assignment disappears. | `lib/services/automatic_vehicle_tracking.dart` (`AutomaticVehicleTracking`), `lib/services/vehicle_tracking.dart`, `lib/screens/location_access_gate.dart`, `lib/screens/driver-responder/responder_app.dart`, `mdrrmo/app/Http/Controllers/MobileLocationController.php`. |
| **23 - Search and date filters** | Server-side case-insensitive search and From/To dates apply before cursor pagination, including records outside the loaded page. Dates use Asia/Manila civil-day boundaries; schedules filter their service date. Ownership remains enforced. Residents can search reports, schedules and notifications; responders can search authored reports, dispatch history and notifications. Staff collections use the same browser/filter contracts. | `lib/screens/record_browser_screen.dart` (`RecordBrowserScreen`, `pickRecord`), `lib/screens/search_screen.dart`, `mdrrmo/app/Support/MobileFilters.php`, `MobilePage.php`. |
| **25 - Mobile admin/dispatcher interface** | Added staff sign-in/onboarding and session restoration using server-authoritative roles. Both staff roles get operational dashboards, report details/acknowledgement/invalidation/manual team assignment, schedule confirmation/decline/completion, teams and member rosters, shifts, vehicles and a fleet map. Admins additionally manage accounts/resident approval, incident categories, audit logs and the automatic-dispatch switch. Dispatcher access to administrative actions is denied on the server. | `lib/screens/operations_app.dart` (`OperationsApp`, `OperationsDetails`), `lib/screens/fleet_map_screen.dart`, role/auth files, `mdrrmo/app/Http/Controllers/MobileOperationsController.php`, `MobileStaffAccountsController.php`, `MobileFleetController.php`, `MobileCatalogController.php`. |
| **26 - Automatic dispatch** | Admin-controlled, password-confirmed persisted switch, initially off. After a report submission commits, the observer attempts allocation when enabled. An eligible match requires an active team declaring the incident capability (exact category name or explicit `*`), a currently on-shift active driver without an active assignment, and an available unassigned vehicle. Allocations use locks, the shared dispatch service, notifications, events and a System audit entry. Unmatched reports remain pending with a reason; retries are fair so an unmatched backlog cannot permanently block other new eligible reports. | `mdrrmo/app/Services/AutomaticDispatch.php`, extended `DispatchService.php`, `app/Observers/AutomaticDispatchObserver.php`, `app/Console/Commands/AutoDispatchReports.php`, `routes/console.php`, admin settings in `OperationsApp`. |

### GPS integration contract and operational limits

- Android requests foreground location and foreground-service/location permissions. Background mode starts a location foreground service with a persistent notification; this implementation does not request unrestricted background-location permission outside that service. iOS declares location usage descriptions and the location background mode. macOS declares location usage and the personal-location entitlement. Automatic background mode is used only on Android/iOS; other supported targets use foreground sharing, subject to their platform location support.
- `POST /driver-responder/tracking/sessions` validates the automatic-sharing notice version and requested report binding (or consent/version for older manual clients), ownership, active driver membership and the assigned active dispatch. Sessions are tied to driver, vehicle, report and issuing access token. Starting a session stops previous sessions for that vehicle.
- `POST /driver-responder/tracking/sessions/{session}/ping` is driver-write scoped and limited to 30 requests/minute. Coordinates, speed, heading, accuracy (maximum 200 m), recent observation time and sequence are validated. Old sequences and older observations do not move a vehicle backwards. The client normally sends at most one request every 10 seconds and coalesces overlapping sends.
- The API updates the existing `vehicles.lat/lng/speed/heading/last_updated_at` fields and broadcasts the existing `VehicleLocationUpdated` event to the website's private dispatch channel. Vehicle timestamps represent the observation time. No separate website database or simulated location data is used.
- `DELETE /driver-responder/tracking/sessions/{session}` stops sharing. A three-minute renewable server lease expires when pings stop. The dispatch workflow stops related sessions on terminal transitions. If the device cannot notify the server when stopping, expiry prevents future accepted updates; the native subscription is still stopped locally.
- `FleetMapScreen` displays last known positions, marks older readings stale, fits the fleet, retains OSM attribution and refreshes every 30 seconds while open. It is polling, not an added push/realtime subscription.
- This feature stores session/consent metadata and the last vehicle position, not breadcrumb history. Route guidance, ETA, automatic odometer distance and historical route playback remain outside this batch. Actual native permission dialogs/background delivery remain **unknown until physical-device verification**.

### Staff permissions and workflows

| Role | Mobile access |
|---|---|
| Resident | Existing resident module, own records/search. No staff APIs. |
| Driver/responder | Existing responder module, own/assigned records/search, explicitly started active-vehicle location sharing. No staff APIs. |
| Dispatcher | Staff dashboard, report operations/manual dispatch, schedules, teams/members/shifts, vehicles/fleet locations and authorized automatic retry. Cannot manage accounts, categories, audit logs or the automatic-dispatch policy. |
| Admin | Staff operations plus account creation/editing/activation, resident approval, incident-category CRUD, audit logs and password-confirmed automatic-dispatch settings. |

Staff tokens carry `staff-read` / `staff-write`; admin tokens additionally carry `admin-manage`, alongside `session`. Existing resident/driver token scopes remain unchanged. Public registration still creates only a pending resident; selecting Staff on the device does not grant staff privileges. Account roles are immutable after creation, self-disable is denied and at least one active administrator is retained. Mobile account management deactivates/suspends accounts rather than exposing destructive hard deletion of retained emergency records. Existing operational retention/deletion-request review remains an institutional process, not automatic erasure.

Team members/shifts are scoped to their parent team. Cross-team roster IDs are rejected; active assignments block disabling a team or changing an assigned driver's membership and block vehicle identity/team edits. Manual dispatch now requires an active driver on the selected team rather than silently assigning an arbitrary non-driver member. Administrative and operational changes write audit entries. Shared patient-care forms are viewable to authorized staff in report details; driver editing remains governed by the existing assigned-driver policy.

### Automatic-dispatch use and retry behavior

1. Sign in with an existing admin account through the new **Admin / Dispatcher** entry. Existing staff must sign in to receive mobile staff token scopes.
2. Configure an active team's incident capabilities, linked active driver members, a current on-shift roster and an available vehicle. Empty or mismatched capabilities do not qualify for automatic allocation. `*` is an explicit declaration of capability for all incident types.
3. Open **Automatic dispatch settings**, select Enabled and enter the administrator's current password. The database starts with this switch off; no live report was automatically dispatched by this implementation session.
4. New committed reports trigger a bounded drain. Previously untried reports are ranked critical/high/medium/low and then oldest first. Waiting reports are rotated by oldest attempt for fair retries. Automatic allocation never intentionally gives an already busy driver another assignment; staff can still make explicit manual assignments under the shared workflow.
5. **Retry waiting automatic dispatches** performs an authorized immediate retry. `php artisan mobile:auto-dispatch` is also registered with `Schedule::command(...)->everyMinute()->withoutOverlapping(5)` for unattended retries. A running Laravel scheduler is an operational prerequisite; it was not started or installed by this batch. The command and observer were exercised only against isolated test databases.
6. The staff report details show automatic-attempt state/reason. A missing resource leaves the original report pending; it does not fabricate a successful assignment or roll back a received emergency report.

### Database changes, testing and remaining work

- Applied additive migration: `2026_11_03_120057_add_mobile_operations_and_tracking.php`; new `automatic_dispatch_settings`, `automatic_dispatch_attempts`, `vehicle_tracking_sessions` tables. Existing business records were retained; the switch row defaults to false.
- Corrected the previous medium migration's **down** path to drop the last-seen index before its column, exposed by SQLite rollback testing. Its already-applied schema creation behavior was not changed.
- Added shared `AppScaffold` Material ancestry for the Forui page layout. New browser/edit-form widget tests caught missing Material ancestry for native text/dropdown controls, including the previous batch's shared edit form. The fix preserves the existing Forui layout and enables those controls to render.
- Backend regression tests: `tests/Feature/MobileOptionalFeaturesTest.php`, `AutomaticDispatchObserverTest.php`, and the existing suites. They cover staff scopes, denied roles, category mutations, cross-team roster rejection, account protection, schedule terminal rules, filtered owner-scoped reads, GPS token/ownership/sequence/time/lease checks, dispatch priority/capability/shift/free-driver requirements, backlog fairness, System auditing and allocation only after commit.
- Flutter regression tests: `test/vehicle_tracking_test.dart`, `record_browser_test.dart`, `operations_screen_test.dart`, staff-role additions to `auth_service_test.dart`, plus all earlier suites. They cover permission failures, invalid GPS readings, foreground/background lifecycle, stopped/expired sessions, late permission results, server search resetting pagination, staff navigation and preserved form input on failure.
- **Still deferred:** deployment/network and physical-device verification, release signing, Windows native plugin linking prerequisite, actual email delivery and broader accessibility/device checks. Verify Android/iOS background tracking and native file/dialer behavior during the authorized device phase. Scheduler hosting remains an operational setup task.
- **Still optional/unimplemented:** directions/ETA/hospital recommendations; push delivery and external notification deep links; full offline drafts/automatic synchronization; incident evidence attachments; ratings/feedback; translations; additional lower-priority cleanup, profiling, branding and CI work. The existing uncertain-submission outbox remains available.

---


> **Previous implementation update - medium priorities, 2026-11-03:** The agreed medium-priority functionality batch is implemented and database-backed. This section supersedes the historical audit and earlier implementation notes below. Deployment verification and release signing remain deferred by the user. No optional GPS/background tracking, navigation/ETA, push delivery, evidence attachments, mobile administration, or automatic dispatch was added.
>
> **Verified:** Dart analysis reports no issues; **56 Flutter tests** and **84 backend tests / 552 assertions** pass. Backend tests use in-memory SQLite. Migration `mdrrmo/database/migrations/2026_11_03_113745_add_mobile_record_workflows.php` was applied successfully to local PostgreSQL (batch 8). Existing reports and medical records were retained. The unrelated website index migration was not applied.
>
> **Verification limits:** native image-picker/dialer behavior, actual email delivery, external map-tile availability, visual accessibility and physical-device workflows remain unverified. `flutter pub get` resolved/downloaded the new official Flutter plugins and updated the lockfile, then reported that Windows native plugin linking needs Developer Mode/symlink support. Windows settings were not changed. This is a native-build prerequisite, not a failed Dart analysis or test run.

### Current medium-priority feature status

All entries below are implemented and covered by automated checks where relevant. Device/deployment verification is a separate deferred activity.

| Feature | Implemented behavior and principal files |
|---|---|
| Resident report details | `lib/screens/record_details_screen.dart` (`RecordDetailsScreen`) fetches the current owner-scoped record, reference, description, status, location, assignment metadata and real event times. Resident History cards open this screen. `mdrrmo/app/Http/Controllers/MobileRecordsController.php` authorizes reporter ownership or driver assignment; knowing an ID does not grant access. |
| Permitted report edits / withdrawal | Residents can edit only their own pending reports; report type, description, location, reporter type and coordinates are validated. Locked writes recheck status. SHA-256 revisions of stored attributes reject stale edits with 409, including edits in the same second. Withdrawal records a reason and timestamp, preserves the report and sends one notification. The legacy dispatch status is `invalid` to keep existing dispatch exclusion rules compatible; explicit `withdrawn_at` makes mobile status `withdrawn`, distinct from a dispatcher rejection. Acknowledged/dispatched reports cannot be withdrawn through mobile. |
| Schedule details / edits | Schedule cards open fresh details. Only owner pending requests are editable; confirmed requests retain the existing permitted cancellation path. Future Asia/Manila date/time, service catalog, address and notes are validated. Website AM/PM times are normalized for editing. Locked writes reject stale revisions. |
| Notification record links | `ResidentNotification.relatedId` / `relatedKind` preserve supported report/schedule links. Notification taps mark the item read and open the authorized details API even when the record was absent from the currently loaded page. Unknown related classes do not become routes. |
| Responder inbox | `ResponderRecordsScreen(inbox: true)` replaces the bell snackbar with a paginated private inbox and per-item read actions. `DriverNotification` receipts are created for dispatch assignments, submitted reports and shared workflow status changes. The migration backfilled existing active assignments. Bootstrap supplies the total unread count independently of the page. |
| Driver-authored history / receipts | `ResponderRecordsScreen` displays paginated reports authored by the signed-in driver, including pending reports. The header receipt icon opens it. This list remains available after reopening the app and is separate from completed dispatch history. The driver emergency form switches to a read-only confirmation with reference, details link and Done after successful submission. |
| Multiple assignments | Bootstrap returns all active assignments; `ResponderState.assignments` and the Home selector preserve the selected record across refresh, use its vehicle ID and expose each assignment's details/status actions. Finishing one does not erase other assignments. |
| Resident account editing / avatar | `AccountScreen` loads and saves resident name, PH phone and structured address. Email, approval and role are not editable through this endpoint. `MobileAccountController` validates image MIME/content, dimensions and size (2 MB; JPEG/PNG/WebP); stores randomized private paths; and serves only the signed-in user's avatar. `file_selector` provides native file selection; macOS gets the required user-selected read-only entitlement. |
| Password changes / recovery | Login links to `PasswordRecoveryScreen`. Public recovery uses rate-limited generic responses and Laravel's separate mobile password broker (`mobile_password_reset_tokens`), hashed expiring single-use codes, a 60-minute lifetime and one-minute issuance throttle. `MobilePasswordReset` emails the code for entry in the app. Reset revokes all mobile tokens; password change requires the current password and revokes other mobile sessions. Existing mail configuration is used; delivery was not tested or reconfigured. |
| Account deletion requests | Account tools require current-password verification to submit or cancel a persisted request in `account_deletion_requests`. Repeated submissions do not create duplicates. The screen shows pending/cancelled state and an explicit retention notice. This implements a review request, not automatic erasure: the account and emergency/medical history remain intact. Office retention decisions and any subsequent de-identification require a separate authorized administrative process; no fabricated retention duration or automatic deletion job exists. |
| Patient-care viewing / editing | A separate `PatientCareScreen` opens from assigned report details. It loads/saves the existing `ReportForm` driver and emergency sections, vital signs and clinical fields using `SavePatientReportRequest`. Only the assigned driver on dispatched/resolved reports may use it. Required fields, lengths, age, sex and HH:mm times are checked; locked saves reject stale forms. Resident reporter access does not expose this confidential form. |
| Actual trip information | `dispatch_trips` / `DispatchTrip` store actual destination, server-observed start/on-scene timestamps, driver-entered pickup/arrival and driver-reported distance. Start/on-scene transitions save their real event times and driver/vehicle snapshot. The trip form can capture the current time or accept historical corrections; it validates ordering, future times and ownership. `TripSummary` derives transport duration only when both pickup and arrival exist. Missing values show Not recorded; report creation/resolution are never fabricated pickup/arrival. Distance is explicitly manual, not GPS measurement. |
| Team contact / presence | Team payloads include the linked driver's contact number. Home opens a `tel:` dialer through `url_launcher`, disables missing numbers and reports launch failure. Presence now means mobile activity observed in the past 90 seconds, with last-seen writes limited to once per 30 seconds; administrative active status alone no longer implies online. The UI labels that observation window. |
| Map resilience / centering | Shared `ResilientTiles` replaces all three OSM TileLayers, provides tile-failure feedback and a retry stream while retaining the pin. Driver map creation/assignment changes center on the incident; recenter uses the current incident rather than a fixed service-center coordinate. Attribution remains visible. No GPS or routing was added. |
| Server incident styling | `IncidentType.fromJson` consumes server hex colors with readable foreground contrast; names and inferred fallback icons remain compatible with arbitrary server categories. Invalid/missing colors use the existing fallback. Incident priorities continue to be authoritative on the server and in driver type options. |
| Remaining empty states | Added actionable empty incident-category feedback/retry, no recent-report messaging and no service-request messaging. Inbox/authored-report screens distinguish loading, empty, failure/retry and older-record pagination. Form save failures retain entered values. |

### Medium-priority database and API inventory

- New schema: `drivers.last_seen_at`; `emergency_reports.withdrawn_at` / `withdrawal_reason`; `dispatch_trips`; `driver_notifications`; `account_deletion_requests`; `mobile_password_reset_tokens`. The migration is additive, backfills active-assignment inbox entries and does not configure a database or rewrite existing incident content.
- Resident APIs: GET/PUT `/resident/reports/{id}`, PATCH `/resident/reports/{id}/withdraw`, GET/PUT `/resident/schedules/{id}`. Existing cancel, notification and paginated list routes remain in use.
- Driver APIs: GET `/driver-responder/authored-reports`, GET `/driver-responder/notifications`, PATCH `/driver-responder/notifications/{id}/read`, GET `/driver-responder/reports/{id}`, GET/PUT `/driver-responder/reports/{id}/patient`, PUT `/driver-responder/reports/{id}/trip`. Role/read/write abilities remain enforced.
- Account APIs: GET/PUT `/auth/mobile/account`, authenticated GET and multipart POST `/auth/mobile/avatar`, PUT `/auth/mobile/password`, PUT `/auth/mobile/deletion-request`, public rate-limited POST `/auth/mobile/forgot-password` and `/auth/mobile/reset-password`.
- Regression coverage: `mdrrmo/tests/Feature/MobileRecordsTest.php`, `test/medium_models_test.dart`, additions to `test/responder_state_test.dart`, plus all earlier suites. Fixed the shared dispatch notification path to recognize resident versus driver reporter types.
- Added Flutter dependencies: `file_selector ^1.1.0`, `url_launcher ^6.3.3`; no backend dependency changes. Physical platform linking/behavior remains subject to the verification limits above.

### Remaining work after the medium batch (historical; see current update above)

- Deferred by user: deployment/network/physical-device verification and release signing.
- Native Windows prerequisite: enable Developer Mode/symlink support before completing native plugin linking/builds, when the user is ready. No operating-system settings were changed by this batch.
- Verify configured email delivery, image selection and phone dialer on supported physical targets during the authorized environment/device verification.
- Office review of individual deletion requests and institution-specific retention decisions remain operational work; this batch does not perform destructive erasure.
- Lower-priority accessibility/device checks, broader cleanup/CI/documentation and previously listed optional features remain outside the agreed functionality batch.

---


> **Latest implementation update ? high priorities, 2026-11-03:** All nine remaining high-priority implementation items from the follow-up backlog are complete. Deployment verification and release signing remain explicitly deferred at the user's request. Earlier audit findings and the first-batch note below are historical snapshots, not the current remaining-task list.
>
> **Verification:** the Dart analyzer reports no issues; all **50 Flutter tests** and **69 backend tests / 422 assertions** pass. Tests cover durable retries, stale replay responses, owner-scoped pagination, token abilities/expiry, rate limits, consent, vehicle selection/authorization, refresh gaps, concurrent account operations, startup recovery and malformed responses. Full physical-device/deployment verification is still deferred.
>
> **Local database:** migration `2026_11_03_104739_create_mobile_submissions_and_resident_consents_tables.php` was applied successfully to the configured **local PostgreSQL** database. It adds `mobile_submissions` and `resident_consents`; it does not rewrite existing business records. The unrelated website index migration remains pending. Backend regression tests continue to use in-memory SQLite rather than the local business database.

### Current high-priority implementation status

| Item | Result and principal files |
|---|---|
| Duplicate-submission protection | Required UUID idempotency headers for report/schedule/registration creates; transactionally stored, encrypted server response receipts and request fingerprints in `mdrrmo/app/Http/Middleware/MobileIdempotency.php`. Conflicting reuse returns 409; identical retries replay the original result without another record/notification. |
| Recovery after uncertain writes | `lib/services/pending_submissions.dart` stores attempted report/schedule submissions in secure storage, isolated by account and API environment. `PendingSubmissionsScreen`, reachable from both module headers through the outbox icon, confirms the saved request using its original key. Changed details cannot silently replace an unconfirmed request. Definite 422 validation failures release the entry for correction; timeouts, cancellations, 5xx and malformed success responses retain it. Replayed resident submissions refresh current server data instead of restoring an old status or duplicating unread counts. This is recovery of attempted submissions, not full offline drafting or background synchronization. |
| Pagination | New owner-scoped GET resident report/schedule/notification endpoints and paginated responder history use descending numeric IDs, `before`, a maximum `limit` of 50, and `next_before`. `MobilePage`, `RecordPage`, `mergeRecords`, state load-more methods and `PageLoader` provide older records, retry controls, de-duplication and refresh-gap handling. |
| Validation | `MobileValidation` and `InputValidation` align PH phone normalization, first/last-name limits, field lengths, passwords, valid coordinates and future schedule times. Service schedule civil time is Asia/Manila; API timestamps retain their existing timestamp handling. Registration requires the current published consent version. |
| Concurrency protection | Client sign-in and logout operations are guarded across service instances; logout dialogs are guarded by `logoutFrom`. Notification writes and domain mutations are serialized by state guards. Session writes reject late results belonging to an older token. Server submission transactions and unique keys protect concurrent retries. |
| Vehicle permissions | `VehiclePolicy` permits active driver memberships (`Driver` / `driver` / `Driver/Responder` / `driver/responder`) in active teams, and denies a vehicle assigned to another driver. Multiple eligible vehicles require an explicit ID, exposed through vehicle selectors in Home and Driver Form. Vehicle identity cannot change during an active assignment. Selection and permission checks are repeated against locked records on writes. |
| Authentication policies | Tokens expire after seven days and carry role-specific read/write plus session abilities; routes enforce these abilities. Older tokens are also bounded by Sanctum's seven-day lifetime. Mobile login is limited to five attempts/minute per email+IP and thirty/minute per IP; registration is limited to ten/hour per IP. Suspended accounts cannot restore mobile sessions. The unused unrestricted token-minting endpoint was removed. |
| Consent and privacy | `/auth/mobile/policy` publishes versioned consent and factual privacy/retention information. Registration displays the published statement, requires a fresh explicit agreement and saves its version, statement and trusted server timestamp in `resident_consents`. Existing users are not assigned fabricated historical consent. The text makes no invented automatic deletion-period promise. Client `.env` currently contains public API/debug configuration only; local env files are ignored and a public `.env.example` is provided. |
| Startup and API resilience | `AppStartup` catches initialization/storage failures and provides retry UI without deleting a saved session. Both API services cancel module-owned requests on disposal. State applies validated snapshots, retains previous data on refresh failure and preserves expanded histories. Unknown report/dispatch statuses are displayed as unknown; unsupported vehicle/priority data fails visibly instead of being mislabeled. Recovery only sends to known submission endpoints, and server internal errors are presented without raw diagnostic details. |
| Deployment verification | **Deferred ? do not begin until requested.** |
| Release signing | **Deferred ? do not begin until requested.** |

> **Implementation update — 2026-11-03:** The original audit below is retained as a baseline. The first implementation batch now repairs the relative imports and standardizes Material widgets on Forui's `material_ui` dependency; fixes all five vehicle-type round trips and web/mobile schedule-time parsing; adds startup session restoration, 401 handling, local logout cleanup, approval-state messaging and submission guards; adds manual/foreground/resume refresh without replacing resident forms; and adds persisted schedule notes/cancellation with ownership and terminal-state checks. Resident report references and the server-wide unread count are retained. Shared form layouts, readable API errors, empty-name handling, accurate report-time labels and Android/macOS network permissions were also addressed.
>
> **Database changes in application code:** resident report/schedule plus notification creation and driver/vehicle profile edits now use transactions; mobile assignment updates lock/select the incident's vehicle and use the existing shared completion workflow for report notifications, audit entries and events. The shared workflow now sends resident notifications only to resident reporters. No schema migration or live database reconfiguration was needed or performed.
>
> **Verification:** Flutter analysis reports no issues. All 23 Flutter tests and all 50 backend tests (293 assertions, including 14 mobile API tests) pass for this batch. Backend tests use the configured in-memory SQLite test database. Production data, physical-device networking, release signing, GPS, push delivery, pagination, detailed record editing, telemetry and idempotent submissions remain outside this batch. Foreground refresh is 30-second polling, not a push-notification implementation. Offline logout clears the device token; remote revocation is not guaranteed while the server is unavailable.

## 1. Project Overview

**Analysis date:** 2026-11-03. **Application:** `mdrrmo_flutter`, version `1.0.0+1`.

This is a Flutter emergency reporting and response application for MDRRMO/Balagtas Rescue. Residents can register, sign in, report incidents, request non-emergency services, inspect their report history, and read notifications. Drivers/responders can inspect assignments and team members, change vehicle availability, advance dispatch status, edit driver/vehicle details, and submit emergency reports for dispatcher review.

The workspace contains two applications: `mdrrmo_flutter/` (the subject of this document) and `mdrrmo/` (a Laravel backend and separate web application). The backend was inspected where needed to verify Flutter integrations. Its web screens are not Flutter screens and are outside this screen inventory. The existing `mdrrmo/PROJECT_ANALYSIS.md` was not modified.

### Scope and evidence limitations

- All **31 Dart files under `mdrrmo_flutter/lib/`** and the single Dart test were inspected, together with the dependency manifests, asset inventory, relevant native/web configuration, mobile backend routes/controllers/models, migration definitions, and mobile API test source.
- This is a **static code audit**. No application, API request, database query, build, analyzer, or test was executed. Flutter commands can update caches and generated files, and backend tests can write databases; the authorization permits changes only to this document.
- Actual deployment, API reachability, installed database engine, applied migrations, database contents, secure-storage behavior, visual rendering, and test outcomes are **unknown**. Existing build output does not verify the current source.
- Two nonexistent relative import targets are verified build blockers. Consequently, no complete running application workflow is certified as completed.
- Every endpoint called by the Flutter services has a matching Laravel route and controller implementation. Core forms are **not merely dummy UI**. Source-level database wiring is distinguished below from runtime verification.
- Paths beginning with `lib/`, `test/`, `android/`, etc. are relative to `mdrrmo_flutter/`. Paths beginning with `mdrrmo/` are relative to the workspace root.

### Status definitions used throughout

| Status | Meaning |
|---|---|
| **Completed** | A bounded local behavior is fully implemented and requires no backend, or a backend-dependent feature is fully verified. No backend-dependent end-to-end workflow meets the latter standard in this audit. |
| **UI Only** | A visual affordance exists but its intended functional operation has no implementation. |
| **Not Connected** | A relevant implementation exists, but the application does not connect it to the backend or consume the available service. |
| **Partially Implemented** | Some behavior exists, but functional gaps, defects, or verification blockers remain. Existing server-backed features retain this conservative status until the build blockers and runtime checks are resolved. |
| **Not Implemented** | No Flutter implementation was found. This does not necessarily mean the separate website lacks the feature. |

## 2. Technology Stack

### Flutter dependencies

Constraints below come from `pubspec.yaml`, not an assertion about the latest available package releases.

| Dependency | Declared constraint | Actual use / observations |
|---|---|---|
| Dart | `^3.13.5` | Records, switch expressions, enums, asynchronous services, typed models. |
| Flutter | SDK | Widgets, Material controls, navigation, animations, platform integration. Lockfile requires Flutter `>=3.47.0`; installed SDK compatibility was not tested. |
| `forui` | `^0.27.7` | `FTheme`, scaffolds, headers, buttons, text fields, select controls, dialogs, navigation and Lucide icons. |
| `flutter_localizations` | SDK | Global delegates and Forui locale support registered in `MdrrmoApp`. Application strings remain English literals. |
| `flutter_map` | `^8.3.2` | Resident incident pinning, responder assignment map, responder emergency pinning. |
| `latlong2` | `^0.10.1` | `LatLng` map coordinates. |
| `http` | `^1.6.0` | Authentication requests in `AuthService`. |
| `dio` | `^5.11.1` | Resident/responder requests, shared base URL and token interceptor. |
| `flutter_secure_storage` | `^11.2.0` | Authentication token storage under `auth_token`. |
| `flutter_dotenv` | `^6.0.1` | Loads bundled `.env`; reads `API_URL`. |
| `shared_preferences` | `^2.5.6` | Remembers selected account type; does not store report or assignment data. |
| `cupertino_icons` | `^1.0.8` | No `CupertinoIcons` references or explicit package imports found in application/test source; candidate unused direct dependency. |
| `flutter_test` | SDK, development | One incident-type model test. |
| `flutter_lints` | `^6.0.0`, development | Included in `analysis_options.yaml`; analyzer results unknown. |

`main.dart` directly imports `package:material_ui/material_ui.dart`, but `material_ui` is **transitive**, not declared directly in `pubspec.yaml`. The lockfile and existing package configuration contain `material_ui` 1.8.0. Cached Forui 0.27.7 source also imports this package. Most application files instead import `package:flutter/material.dart`; see the compatibility risk in Section 12. This is not a missing-package finding.

Transitive libraries cover Forui icons, map geometry/projections, networking adapters, native storage/preferences implementations, and test infrastructure. No application imports of Firebase, Supabase, a local relational database, a location plugin, a push-notification SDK, or a websocket client were found. Do not mistake generated native plugin files for application features.

### Backend and external services

- Laravel `^13.17`, PHP `^8.3`, Sanctum `^4.0` and Eloquent, according to `mdrrmo/composer.json`.
- Separate website uses Inertia; Laravel Reverb and broadcast events exist server-side, but Flutter does not subscribe to them.
- Backend `config/database.php` selects `DB_CONNECTION` with a SQLite fallback. The actual configured/live database and schema state are **unknown**; Flutter does not connect directly to SQL.
- All three Flutter maps request tiles from `https://tile.openstreetmap.org/{z}/{x}/{y}.png`, include attribution, and declare a user-agent package name. These are tile requests, not geocoding, navigation, or device positioning.
- The current Flutter `.env` has an HTTP `API_URL` ending in `/api`. Both clients have an Android-emulator HTTP fallback. Environment values and credentials are intentionally not reproduced here.

## 3. Project Architecture

### Layers and ownership

The project uses a small, manually composed layered architecture, rather than Bloc, Riverpod, or the `provider` package:

1. `main.dart`: initialize bindings, load environment, initialize preferences, start `MdrrmoApp` with themes/localization and splash.
2. `screens/`: local form/navigation state, validation, dialogs, map interactions and presentation.
3. `state/`: `ResidentState` and `ResponderState` extend `ChangeNotifier`; their `InheritedNotifier` scopes provide access and rebuild dependents. These are the project's provider equivalents.
4. `data/api/`: service wrappers around endpoint requests and basic response-shape validation.
5. `data/`: domain models, parsing and the global Dio client.
6. `services/auth_service.dart`: separate HTTP client path for auth plus secure token storage.
7. `ui/` and `widgets/`: reusable presentation, input and navigation components.

`ResidentApp` owns and disposes `ResidentState`; `ResponderApp` owns and disposes `ResponderState`. Both states start loading in their constructors using `unawaited(load())`. The resident bootstrap loads profile, incident types, reports, schedules, and notifications in one response. The responder loads bootstrap and history together with `Future.wait`; failure of either prevents a fully successful initial load.

There is no repository abstraction, shared auth/session notifier, dependency-injection container, local domain-data cache, background sync engine, or generated serialization. Resident/driver API clients can receive a Dio instance and state constructors accept service overrides; authentication constructs its own requests/storage without equivalent injection.

### Navigation flow

```text
main -> MdrrmoApp -> SplashScreen (2.4-second timer)
  no stored account type -> RoleSelectScreen
    Resident -> RegisterScreen -> dialog -> pop to previous screen
    Already registered -> LoginScreen
    Driver / Responder -> remember type -> LoginScreen
  stored account type -> LoginScreen

LoginScreen -> AuthService.login -> destination selected from SERVER role
  resident -> ResidentApp -> ResidentScope -> ResidentShell
    History | Report | Home (initial index 2) | Schedule | Notification
    header profile icon -> resident profile bottom sheet -> logout
    Home report actions -> Report tab
    Report: category/reporter -> details + map pin -> sent -> Done/Home
  driver/responder -> ResponderApp -> ResponderScope -> Shell
    Home (initial index 0) | History
    Home -> DriverFormScreen or EmergencyFormScreen (scope passed explicitly)
    History card -> DispatchDetailsScreen (passes existing Dispatch object)
    header -> assignment-count snackbar or logout
```

All route transitions use imperative `Navigator` calls and `MaterialPageRoute`/`PageRouteBuilder`. There are no named routes, URL/deep-link configuration, or route guards. Authentication role enforcement exists in Laravel, so the remembered role is not the security boundary. There is no startup token check: `AuthService.getMe()` exists but has no caller.

`IndexedStack` preserves tab state and creates all tab children, including hidden ones. Resident load errors replace the entire tab content with a retry screen. Responder loading/errors are handled mostly in Home; History can appear empty during a load failure.

## 4. Folder and File Structure

### Top-level folders and configuration

| Path | Purpose / finding |
|---|---|
| `lib/` | All authored Dart application modules; complete file inventory below. |
| `assets/images/mdrrmo-logo.webp` | The only discovered application image in this asset folder; used by `LogoMark`. |
| `test/resident_models_test.dart` | One test: server-defined incident name is retained and flood styling selected. |
| `android/` | Gradle project, Kotlin `MainActivity`, resources, generated plugin registration and manifest variants. |
| `ios/` | Swift app/scene delegates, Xcode project/workspace, plist, launch assets and template test. |
| `macos/` | Swift desktop runner, Xcode configuration, entitlements and template test. |
| `windows/` | C++ runner, CMake, resources and generated plugin registration. |
| `linux/` | C++/GTK runner, CMake and generated plugin registration. |
| `web/` | HTML bootstrap, PWA manifest and default icons. No application-specific web service integration. |
| `.env` | Bundled client environment configuration; public in distributed assets, unsuitable for secrets. |
| `pubspec.yaml` / `pubspec.lock` | Dependency constraints/resolution, assets, app version and Dart constraint. |
| `analysis_options.yaml` | Flutter lints; generated/native/web directories excluded from Dart analysis. |
| `README.md` | Uncustomized Flutter starter instructions. |
| `.gitignore` | Excludes build/cache/IDE outputs; does not list `.env`. Actual repository tracking status is unknown. |
| `.metadata`, `mdrrmo_flutter.iml`, `.idea/` | Flutter project metadata and IDE configuration. |
| `.dart_tool/`, `.flutter-plugins-dependencies`, `build/` | Existing generated package/build outputs. Not evidence that current source builds. |
| `flutter_01.png` | Existing image outside declared image assets. No source reference found; provenance/purpose unknown. |

### Complete Dart source inventory

| File | Classes / responsibilities |
|---|---|
| `lib/main.dart` | `main`, `MdrrmoApp`: initialization, root app, themes, localization, Forui wrappers. |
| `lib/app_prefs.dart` | `AccountType`, `AppPrefs`: read/write/remove remembered role and legacy responder string compatibility. |
| `lib/services/auth_service.dart` | `AuthService`: login, register, token retrieval, current user, logout, first validation-error extraction. |
| `lib/data/api_client.dart` | Global `dio`: URL, 10-second connection/receive timeouts, JSON accept header, bearer-token interceptor. |
| `lib/data/api/resident_service.api.dart` | `ResidentApi`: bootstrap, create report/schedule, mark one/all notifications read. |
| `lib/data/api/driver_service.api.dart` | `DriverApi`: bootstrap/history/type reads, assignment/availability/profile writes, create report, list-envelope parsing. |
| `lib/data/models.dart` | `Availability`, `DispatchStatus`, `Priority`, `priorityFromApi`, `TeamMember`, `Assignment`, `Dispatch`, `DriverProfile`, `IncidentTypeOption`, `EmergencyReport`. |
| `lib/data/resident_models.dart` | `ReporterType`, `IncidentStatus`, `NotificationKind`, `IncidentType`, `SchedulePurpose`, `ResidentProfile`, `RecentIncident`, `ReportRecord`, `ResidentNotification`, `ScheduleRequest`; presentation metadata and JSON parsing. |
| `lib/state/resident_state.dart` | `ResidentState`, `ResidentScope`: bootstrap lists, unread count, incident-ID mapping, report/schedule writes, notification read writes, disposal notification guard. |
| `lib/state/driver_responder_state.dart` | `ResponderState`, `ResponderScope`: load profile/team/current assignment/history/types, availability/assignment/profile/report operations, saving/error state. |
| `lib/screens/splash_screen.dart` | `SplashScreen`: animated branding, timer, preference-based next screen. |
| `lib/screens/role_select_screen.dart` | `RoleSelectScreen`, `_RoleCard`: role selection, registration/sign-in navigation. |
| `lib/screens/login_screen.dart` | `LoginScreen`: validated credentials, loading/error messages, server-role navigation, account-type change. |
| `lib/screens/register_screen.dart` | `RegisterScreen`: resident details, PH phone/email/password/confirmation validation, local consent, registration request/dialog. |
| `lib/screens/resident/resident_app.dart` | `ResidentApp`: owns resident notifier and scope; contains an invalid state import. |
| `lib/screens/resident/resident_shell.dart` | `ResidentShell`: header/profile sheet, five tabs, initial loading/error/retry. |
| `lib/screens/resident/home_screen.dart` | `ResidentHomeScreen`, `_SosButton`: greeting, report-form actions, recent report cards, reduced-motion-aware pulse. |
| `lib/screens/resident/report_screen.dart` | `ResidentReportScreen`, `_TypeTile`, `_Step`: category/reporter selection, incident details/map pin, submit/confirmation/reset. |
| `lib/screens/resident/history_screen.dart` | `ResidentHistoryScreen`: read-only report list and empty state. |
| `lib/screens/resident/schedule_screen.dart` | `ResidentScheduleScreen`, `_PurposeChip`: six purposes, address/date/time pickers, locked account fields, submission and request list. |
| `lib/screens/resident/notifications_screen.dart` | `ResidentNotificationsScreen`: kind styling, unread indicators, mark-one/all-read, empty state. |
| `lib/screens/driver-responder/responder_app.dart` | `ResponderApp`: owns responder notifier and scope. |
| `lib/screens/driver-responder/shell.dart` | `Shell`: Home/History tabs, new-assignment indicator/snackbar, logout. |
| `lib/screens/driver-responder/home_screen.dart` | `HomeScreen`, `_MapHero`, `_AssignmentCard`, `_StatusCard`, `_TeamCard`, `_QuickActions`: assignment marker/progress/action, availability, roster, forms, retry. |
| `lib/screens/driver-responder/history_screen.dart` | `HistoryScreen`, `_DispatchCard`, `_Filter`: local filtering/day grouping and navigation to dispatch details. |
| `lib/screens/driver-responder/dispatch_details_screen.dart` | `DispatchDetailsScreen`: passed-in driver/route/trip/priority values and back actions. |
| `lib/screens/driver-responder/driver_form_screen.dart` | `DriverFormScreen`: profile/vehicle editing; also duplicates `FormPage` and `FormGroup`. |
| `lib/screens/driver-responder/emergency_form_screen.dart` | `EmergencyFormScreen`: incident/priority/map, patient and contact data, confirm/submit/Done. Imports form layout from driver screen. |
| `lib/ui/form_page.dart` | `FormPage`, `FormGroup`: reusable scrolling form/card groups and pinned submit bar. Used by registration. |
| `lib/ui/kit.dart` | `AppIcons`, `AppType`, `Semantic`, formatters, `AppButtonKind`, `AppButton`, `AppTextField`, `AppPasswordField`, `AppSelect`, `confirmDialog`, `snack`, `LogoMark`, `Pill`, `InitialsAvatar`, `SectionTitle`, `Surface`, `SegmentOption`, `Segmented`, `RouteTimeline`, `StepperBar`, `pushedHeader`. |
| `lib/widgets/res_widgets.dart` | `statusPill`, `IncidentTile`, `_FieldLabel`, `PickerField`, `LockedField`, `ResidentNavBar`, `_NavItem`, `_CenterItem`, `showResidentProfile`. Includes API-backed resident logout. |

Private `State` classes implement their matching widgets' lifecycle/local form state. The application has no additional discovered Dart screen or service outside this inventory.

## 5. Screen-by-Screen Analysis

“Working” below means an actual callback/data path exists in source. It does not assert successful execution of the currently unbuildable application.

### 5.1 Splash — `SplashScreen`

**Path:** `lib/screens/splash_screen.dart`. **Status:** **Completed** for bounded local timer/animation/navigation logic; session restoration **Not Connected**.

- UI: fading/scaling logo, app name, descriptive text, spinner.
- Timer selects role selection or sign-in using `AppPrefs`; timer is cancelled on disposal and navigation checks `mounted`.
- The spinner represents a fixed delay, not a network/session check. There is no call to `getToken`/`getMe` here. A valid stored token does not bypass login.
- Logs account type with `print`; initialization errors before this screen have no recovery UI.

### 5.2 Account selection — `RoleSelectScreen`

**Path:** `lib/screens/role_select_screen.dart`. **Status:** **Completed** for local selection and navigation; onboarding overall **Partially Implemented**.

- UI: two selectable `_RoleCard`s, disabled-until-selected Continue, existing-account shortcut, administrator-issued-account explanation.
- Resident Continue opens registration; driver Continue persists role and replaces route with login. Existing-account action persists the selected role and opens login. These actions have real implementations.
- No driver self-registration is offered; this is an intentional administrator-managed flow.
- First-time resident registration returns to this screen after success instead of proceeding directly to sign-in. Preferences are saved, but the user must select/open sign-in again.
- Preference-write failures have no user-facing handling.

### 5.3 Sign-in — `LoginScreen`

**Path:** `lib/screens/login_screen.dart`. **Status:** **Partially Implemented**, with real backend wiring.

- UI: role pill, “Not you?”, email/password fields, password visibility, submit, registration link for residents, inline error panel.
- Sign In validates email/password, posts credentials through `AuthService.login`, stores the returned token, reads the server role, and replaces the route with the appropriate app.
- “Not you?” removes remembered account type and opens role selection. Resident create-account link opens registration.
- Login has loading text/button disabling and client/timeout/format error messages. A local six-character minimum is imposed by `AppPasswordField`; Laravel login itself only requires a nonempty string.
- Missing: password reset, session restoration, centralized expired-session handling, and approval-status presentation. Returned registration approval is not retained in `ResidentProfile`.
- `_submit` has no `_loading` early guard; password keyboard submission can initiate another request while the button is disabled. The server-issued role is not persisted back to preferences, so signing into a different role can leave the next launch's role label stale.

### 5.4 Registration — `RegisterScreen`

**Path:** `lib/screens/register_screen.dart`. **Status:** **Partially Implemented**, with real database creation.

- UI: full name, PH contact number, home address, email, password/confirmation, consent checkbox, submit, error text, success dialog and back header.
- Validates required inputs, email shape, normalized PH mobile number, password length of eight, matching confirmation, and consent. `AuthService.register` submits to Laravel and waits for HTTP 201 before showing success and remembering resident role.
- Laravel creates an active resident with `registration_status=pending`; password hashing is provided by `User` casts. Cross-role duplicate email lookup and first/last-name validation exist server-side.
- Consent is local only: no consent/version/timestamp is sent or stored by this flow. Name validation in Flutter permits a single name that Laravel rejects. Server field-length limits are not mirrored.
- Submit stays visually enabled through nonnullable `FormPage.onSubmit`; `_loading` prevents duplicate handler execution. Raw exceptions are displayed. No review-status tracker or sign-in handoff after first-launch registration.

### 5.5 Resident app container — `ResidentApp` / `ResidentShell`

**Paths:** `lib/screens/resident/resident_app.dart`, `resident_shell.dart`. **Status:** **Partially Implemented**.

- Owns/disposes state; five functioning tab callbacks and unread badge. Home is initial tab. Header opens the profile sheet.
- Bootstrap spinner, blocking error state and “Try again” call `ResidentState.load`.
- Invalid relative state import prevents compilation as written. Successful bootstrap has no refresh button/pull-to-refresh/lifecycle reload/polling; external updates remain stale.
- Tabs preserve unfinished forms with `IndexedStack`; there is no draft persistence across app restarts.

### 5.6 Resident Home — `ResidentHomeScreen`

**Path:** `lib/screens/resident/home_screen.dart`. **Status:** **Partially Implemented** for live overview; local report navigation **Completed**.

- UI: profile-derived first-name greeting, animated REPORT button, non-emergency report link, up to five recent incident cards, status/time labels.
- Main button confirms opening a report, provides haptic feedback and switches to Report. Non-emergency link switches directly. Neither places a call nor dispatches a team; the UI explicitly explains this.
- Recent incidents derive from actual bootstrap/submitted reports, not static incident samples. Cards have no detail action. Empty recent history has no explanatory placeholder.
- No push/live updates or refresh, hotline dialer, automatic location, or one-tap submission exists. The confirmation/snackbar is local feedback, not evidence that a report has been sent.

### 5.7 Resident Report — `ResidentReportScreen`

**Path:** `lib/screens/resident/report_screen.dart`. **Status:** **Partially Implemented**, with verified source-level create integration.

- UI: victim/witness segmented selection, server-supplied category tiles, back action, address prefill, OSM map, explicit marker selection, reset map, description, Send, sent reference and Done.
- Category selection advances to details. Map taps set coordinates; Reset returns to a fixed Balagtas center and clears selection, not device location. Send requires location, description and an explicitly selected map pin.
- `ResidentState.submitReport` resolves the server category ID, calls `/resident/reports`, parses the persisted response, updates report/recent/notification lists and returns the ID. Success is not fabricated locally. Done resets form and opens Home.
- Send is disabled while sending; exceptions show a snackbar. Laravel validates category existence, reporter type, coordinate ranges, lengths and accepted resident registration.
- Missing: attachment upload, geolocation, geocoding/search, detailed report view, edit/cancel, durable drafts and idempotency. Empty incident-type results produce no helpful category-empty state.
- No client max-length constraints; all categories share a simple description form. Success displays padded numeric ID instead of retaining the backend's `reference`. Resident model import defect blocks the current build.

### 5.8 Resident History — `ResidentHistoryScreen`

**Path:** `lib/screens/resident/history_screen.dart`. **Status:** **Partially Implemented**.

- UI: report type, padded numeric ID, location, reported date/time, status pill and empty state.
- Actual reports arrive through owner-scoped bootstrap. There are no tappable report actions or independent queries here.
- Missing: details, search, filters, pagination, refresh, edit/cancel. Backend bootstrap caps reports at 50; older records cannot be fetched through this screen.

### 5.9 Resident Schedule — `ResidentScheduleScreen`

**Path:** `lib/screens/resident/schedule_screen.dart`. **Status:** **Partially Implemented**, with real create/read integration.

- UI: six selectable purposes, service address, date/time pickers, locked account name/contact/address, Create & Send button, submitted request list and status labels.
- Purpose/address/date/time determine button enablement. Date picker permits today through roughly one year ahead. Submission combines date/time, posts `/resident/schedules`, appends returned request/notification, resets fields and reports success; failures show a snackbar.
- Existing requests are displayed from bootstrap; they are not missing or dummy records. The list has no detail/edit/cancel action and no explicit empty-request message.
- Purposes are hardcoded but currently match Laravel `ResidentController::SERVICES`. They are configuration constants, not fabricated bookings. Available time slots/capacity are not queried.
- Missing validation: earlier time today, slot conflicts and server-style field lengths. Mobile backend accepts any time string up to 20 characters; the website submits `H:i`, while Flutter submits `h:mm AM/PM`.
- `ScheduleRequest.fromJson` recognizes only AM/PM time strings; a website-created `14:30` request is displayed at midnight. Unknown service labels throw and can fail the whole bootstrap.
- No notes input even though backend supports notes. No approval-state handling; mobile schedule creation lacks the accepted-resident check present on the website's schedule creation path.

### 5.10 Resident Notifications — `ResidentNotificationsScreen`

**Path:** `lib/screens/resident/notifications_screen.dart`. **Status:** **Partially Implemented**, with real read-status writes.

- UI: notification cards, relative times, type-derived icons, unread tint/dot, Mark All As Read, empty state.
- Card tap PATCHes one owner-scoped record and updates local unread state after success; Mark All PATCHes all and updates local state. Errors show snackbars.
- No related-record navigation: Flutter model omits `related_id`/`related_type`, and bootstrap does not select them. No push notifications, independent refresh, pagination, delete, or per-action progress/duplicate-request guard.
- Only the latest 50 notifications are loaded; badge counts loaded unread items, not total unread in the database. Mark-all updates all server unread records, including those outside this page.
- Classification is inferred from English message text. `NotificationKind.rate` has styling but is never produced by the parser and has no feedback/rating flow.

### 5.11 Resident profile bottom sheet — `showResidentProfile`

**Path:** `lib/widgets/res_widgets.dart`. **Status:** **Partially Implemented** as account management.

- UI: initials/name, role label, locked contact/address and Log Out; data comes from bootstrap.
- Logout confirms, calls the server to revoke the current token, deletes local token on success, remembers resident type and clears navigation history to login. Error feedback exists.
- Profile is intentionally read-only in current code; edit profile/password/avatar/account deletion have no implementation. Logout has no in-flight guard and does not clear an invalid token when the server returns non-200.

### 5.12 Responder container — `ResponderApp` / `Shell`

**Paths:** `lib/screens/driver-responder/responder_app.dart`, `shell.dart`. **Status:** **Partially Implemented**.

- Owns/disposes state; Home/History navigation, brand header, new assignment dot, notification bell and logout confirmation.
- Bell works only as a snackbar saying “1 new assignment” or “No new notifications”; it does not open a notification inbox or fetch notifications. Count comes solely from the current assignment's `isNew` flag.
- Logout has the real auth revocation/local-delete/navigation path and error feedback.
- No active data refresh after successful bootstrap; a newly assigned incident will not arrive automatically. No notifications-read/acknowledgment model or persisted clearing of “new.”

### 5.13 Responder Home — `HomeScreen`

**Path:** `lib/screens/driver-responder/home_screen.dart`. **Status:** **Partially Implemented**.

- UI: OSM map, optional assignment marker, service-area overlay, recenter control, loading/error/retry, current-assignment card/stepper, availability selector, team roster/activity count and quick actions.
- Marker uses report latitude/longitude from API. Recenter always moves to a fixed service center, not the incident or device; map does not auto-fit assignments. No route polyline or actual vehicle tracking.
- Start Trip / Mark As On Scene / Complete Dispatch call PATCH status. Completion confirms, clears assignment on server-null response and refetches history. Failures surface as snackbars; saving disables assignment button.
- Available / Off Duty PATCHes the vehicle; state prevents changes during an assignment or another save. Team is server-derived. “Active” is calculated server-side from team/member statuses, not measured online presence.
- Team phone glyphs are bare `Icon` widgets: **UI Only** for calling. Team payload contains no contact number. Driver Form and Emergency quick actions push real forms with the shared responder scope and are disabled until initial load succeeds.
- Status control remains visible during load/error; it can attempt a write with incomplete initial data. A single `actionError` from any operation is shown as “Could not save your status,” even for unrelated failures.
- Assignment destination is the constant “Destination not recorded.” Successful status changes do not update `profile.status`, so the driver form can show stale vehicle-status text.

### 5.14 Responder History — `HistoryScreen`

**Path:** `lib/screens/driver-responder/history_screen.dart`. **Status:** **Partially Implemented**; local filters/navigation **Completed**.

- UI: All/Completed/Invalid controls, day headings, time/status/route/driver/vehicle cards and empty state.
- Filters operate on the API-loaded history list; card taps pass the selected `Dispatch` to details. Server query is restricted to assigned driver's resolved/invalid reports, capped at 100.
- Missing: independent loading/error/retry, refresh, pagination, search, date-range filters. A failed bootstrap/history request can look like a legitimate empty history.
- Does not list pending emergency reports created by the driver unless those reports later become that driver's resolved/invalid assignment.

### 5.15 Dispatch Details — `DispatchDetailsScreen`

**Path:** `lib/screens/driver-responder/dispatch_details_screen.dart`. **Status:** **Partially Implemented**; trip metric fields **Not Connected**.

- UI: reference/date/status, driver/vehicle, route timeline, trip duration/distance, emergency type/priority, header back and Back To History.
- Both back actions pop the route. Content is a snapshot of the passed-in history object; no detail endpoint is called.
- Report type, priority, driver, vehicle, reference and reported/resolved timestamps have API sources. Destination is hardcoded; duration and distance are always parsed as zero and displayed as dashes.
- “Patient picked up at” uses the report creation timestamp, which is not a recorded pickup event. `arrivedAt` falls back to report creation time if resolution time is missing. These labels imply events the backend payload does not establish.
- No destination selection, hospital lookup, measured trip telemetry, export, patient-care record display or edit functionality.

### 5.16 Driver Form — `DriverFormScreen`

**Path:** `lib/screens/driver-responder/driver_form_screen.dart`. **Status:** **Partially Implemented**, with real updates.

- UI: prefilled driver name/contact, five vehicle-type options, plate number, read-only status explanation, Save Details and inline errors.
- Required fields and a phone-character/length regex are validated. Save calls `ResponderState.saveProfile` -> PUT `/driver-responder/profile`; Laravel updates both driver and team vehicle. Success parses returned profile and pops; failure remains on the form.
- `_saving` prevents duplicate execution, but the shared layout's button remains visually enabled. There is no explicit success snackbar. Name/contact/plate max lengths and unique-plate errors are not mapped inline.
- Confirmed defect: incoming `fire-truck`, `rescue-van`, `police-car` and `utility-truck` are parsed as Ambulance. Reopening and saving an unchanged form can overwrite a non-ambulance vehicle type. Outgoing state mapping uses the correct hyphenated values, while unused `DriverProfile.apiVehicleType` uses different values.
- The form edits the first vehicle found for the driver's team membership; no vehicle selector/shift assignment management exists.

### 5.17 Responder Emergency Report — `EmergencyFormScreen`

**Path:** `lib/screens/driver-responder/emergency_form_screen.dart`. **Status:** **Partially Implemented**, with real report creation.

- UI: server-provided incident select, priority select, location/map pin, patient name/age/symptoms, contact person/number, error text, confirmation and Submit/Done.
- Required values, age 0–120, phone shape, incident type and explicit pin are checked. Confirmation explains dispatcher review. Submission POSTs patient/contact information and coordinates; Laravel creates a pending report and stores patient data in `victim_info`. It does not assign a responder.
- `_sending`/`_submitted` guard normal repeated submission. Success changes the button to Done and shows a snackbar; Done pops the route. The returned report is discarded by state, so no reference or persistent “my submitted reports” entry is shown.
- Form fields remain editable after success while submission is blocked. Confirmation is awaited before `_sending` is set, leaving a repeated-confirmation window. Button has loading text but no disabled callback through `FormPage`.
- Incident type is auto-selected by mutating `_type` in `build`; selected incident's default server priority is not applied (priority starts Medium). No dedicated type-load retry in this form.
- This is not the separate `ReportForm` patient-care workflow available on the website; no such Flutter edit/save feature was found.

## 6. Existing Features

### Implemented local behavior

| Feature | Status | Evidence |
|---|---|---|
| Remember/select account type | **Completed** | `AppPrefs` uses real `SharedPreferences`; `RoleSelectScreen` has working callbacks. Device persistence not executed during audit. |
| Splash animation/timer | **Completed** | `SplashScreen` timer, animation and cancellation. |
| Tab switching and back actions | **Completed** | Both shells, `pushedHeader`, details back button, form route callbacks. |
| Resident report step navigation/pin selection | **Completed** | Explicit `_Step`, map tap/reset, Done reset. Data submission assessed separately. |
| Responder history local filters/grouping | **Completed** | `_Filter`, predicate and date grouping in `HistoryScreen`. |
| Common local validation/dialogs/haptics | **Completed** | `ui/kit.dart`, form validators and confirmation callbacks; rendering compatibility still requires testing. |
| System theme/localization setup | **Partially Implemented** | Theme mode/delegates exist; Material-family interoperability and translated app strings remain unresolved. |

### Existing database-backed paths

All rows below are **Partially Implemented** at application level because compilation/runtime verification remains outstanding; these paths are genuinely implemented in source.

| Capability | Flutter implementation | Verified server behavior |
|---|---|---|
| Login/session token | `AuthService.login` | Finds account, verifies hash and active/mobile role, creates Sanctum token. |
| Resident registration | `RegisterScreen`, `AuthService.register` | Creates pending resident in `residents`. |
| Current-user lookup | `AuthService.getMe` | `/auth/mobile/me` returns authenticated user; unused by Flutter navigation. |
| Logout | Both shells/profile sheet, `AuthService.logout` | Deletes current token; Flutter then deletes local token. |
| Resident profile/categories/reports/schedules/notifications | `ResidentState.load` | Owner-scoped Eloquent reads via bootstrap. |
| Resident incident submission | `ResidentState.submitReport` | Creates emergency report and resident notification. |
| Schedule submission/list | `ResidentState.submitSchedule`, schedule screen | Creates service schedule/notification; bootstrap reads requests. |
| Notification read state | `markRead`, `markAllRead` | Owner-scoped `read_at` updates. |
| Responder profile/team/assignment/history/categories | `ResponderState.load` | Queries drivers, membership, team vehicles, incident types and assigned reports. |
| Assignment progression | `advanceAssignment` | Validates transition, updates report/vehicle; completion refetches history. |
| Availability | `setAvailability` | Updates real team vehicle status; blocks active assignment. |
| Driver/vehicle profile save | `saveProfile` | Updates `drivers` and `vehicles`; inbound vehicle parsing is defective. |
| Responder emergency report | `submitEmergency` | Creates pending report and JSON patient data; response not retained in client. |

## 7. Features with UI Only

| Visual element | Status | What is missing |
|---|---|---|
| Team-row phone icons (`_TeamCard`) | **UI Only** | No tap handler, telephone URI, contact payload or dialer integration. |
| Destination portion of assignment/history timelines | **UI Only** for real destination data | Layout exists; model always supplies “Destination not recorded”; no destination capture or lookup. |
| Feedback/rating notification variant | **UI Only** for styling | `NotificationKind.rate` icon branch exists, but parser never selects it; no prompt/action/storage. |

The responder bell is **Partially Implemented**, not a dead button: it has a snackbar callback but no inbox. The resident REPORT button is functioning form navigation, not an implemented telephone call. Read-only report cards and locked profile fields have no edit contract and are not mislabeled broken save controls.

## 8. Features Not Connected to Database

| Feature / data | Status | Verified gap |
|---|---|---|
| Startup session restoration | **Not Connected** | Stored token and `AuthService.getMe` exist; splash never uses them. |
| Live assignment/report/schedule/notification updates | **Not Connected** | Initial API reads exist; no polling, lifecycle reload or Flutter broadcast subscription. Laravel broadcast infrastructure alone does not connect Flutter. |
| Trip metrics and real destination | **Not Connected** | `Dispatch`/`Assignment` fields and UI exist; destination constant and zero metrics replace absent server data. |
| Cross-channel schedule time interpretation | **Partially Implemented** | Database reads exist; parser ignores valid website `H:i` values and produces midnight. |
| Consent persistence | **Not Connected** | Checkbox validation exists; registration payload and server creation omit consent evidence. |
| Server incident appearance/defaults | **Not Connected** for these attributes | API supplies category color/priority; resident appearance is name-derived; responder initial priority is local Medium. Incident identities themselves are connected. |
| Optional schedule notes | **Not Implemented** in Flutter | Database/API accept notes, but Flutter has no field/payload entry. |

No form was found that merely reports success without making its intended create/update request. Resident reports/schedules, driver profile and emergency reports all await API results. No missing route was found for a request that Flutter currently issues. Missing workflows need targeted endpoints/client work, not replacement of the existing database integration.

### Hardcoded data versus actual placeholders

- **Actual placeholders:** destination text, zero trip duration/distance, “You”/“Unknown”/missing-vehicle fallbacks, and derived pickup/arrival event labels.
- **Static configuration:** service purposes, role labels, category styling, priority options, workflow labels, English text and Balagtas map centers. These are not dummy persisted records, but some should be server-driven or localized.
- **Actual server data:** resident identity/report/schedule/notification lists, incident type IDs/names, responder profile/team/history/current assignment and assigned-incident marker.
- **Misleading semantics:** team `online` is computed from administrative active statuses; the green map overlay has no measured connectivity source. Neither proves real-time presence.

## 9. Partially Implemented Features

| Area | Implemented portion | Remaining work |
|---|---|---|
| Authentication lifecycle | Real login/token storage/revocation; remembered role | Session restore, invalid-token cleanup, central 401 handling, duplicate-login guard, role-preference reconciliation. |
| Registration/review | Pending resident creation and validation | Review-state UX, consistent accepted-resident policy, first-launch sign-in handoff, persisted consent if required. |
| Report lifecycle | Submit, initial/history read, status labels | Fresh external updates, detail view, reference retention, attachment policy, controlled edit/cancel if required. |
| Schedules | Submit/list/status/notification | Time-format contract, same-day validation, notes, cancel/edit/detail, fresh status and pagination. |
| Resident notifications | Bootstrap/read flags/badge | Total unread count, refresh/push, related-record navigation, pagination and progress guards. |
| Responder assignments | One current assignment and status progression | New assignment delivery, multiple-assignment access, consistent shared backend workflow, correct vehicle selection, return-trip semantics. |
| Team roster | Database members and administrative status | Genuine presence if intended, contact details/dialing, refresh. |
| Driver profile | Persisted identity/vehicle update | Correct inbound type mapping, precise errors/length limits, vehicle selection and atomic backend update. |
| Emergency report form | Validated real pending report | Retain reference/result, list authored reports, close/freeze submitted data, guard confirmation race. |
| Dispatch history/details | Actual driver/report metadata | Destination, trip event timestamps/duration/distance, correct pickup language, page/error states. |
| Maps | Actual network tiles and manual/assigned pins | Tile error UI, offline experience, device positioning/routing if required, fit/recenter assignment. |
| Quality assurance | One Dart test and mobile API test source | Build validation, client/state/widget/integration tests and release-platform checks. |

## 10. Missing Features

These are absent from the Flutter source; product scope/need should be confirmed before implementing optional items.

| Feature | Status | Scope clarification |
|---|---|---|
| Password recovery/change and account deletion | **Not Implemented** | No Flutter screens/services; inspect intended identity policy before exposing endpoints. |
| Resident profile editing/avatar upload | **Not Implemented** | Current profile sheet is read-only. |
| Approval-status screen/restrictions | **Not Implemented** | Backend report submission checks accepted status; Flutter does not represent it. |
| Resident report detail/edit/withdraw | **Not Implemented** | List-only records; mobile API exposes create/bootstrap, not update/delete. |
| Schedule detail/update/cancel | **Not Implemented** | Website cancellation exists; no equivalent mobile route/callback. |
| Responder notification inbox | **Not Implemented** | Bell displays only assignment-count snackbar. |
| Mobile location permission/GPS pings/background tracking | **Not Implemented** | Website has session-authenticated tracking/ping; no Flutter equivalent. |
| Directions, ETA, destination/hospital selection | **Not Implemented** | Map tiles/pin do not supply these functions. |
| Separate patient-care report editing | **Not Implemented** | Laravel `ReportForm`, `SavePatientReportRequest` and website save exist; emergency submission writes different data. |
| Driver-authored pending report history | **Not Implemented** | Existing history is assigned resolved/invalid incidents only. |
| Media/evidence attachments | **Not Implemented** | No picker/upload API use. |
| Offline draft/outbox/retry reconciliation | **Not Implemented** | Domain data lives in memory; no durable submission queue. |
| Push notification registration/delivery and deep links | **Not Implemented** | No device-token SDK/service or related route handling. |
| Ratings/feedback | **Not Implemented** | Only unused notification styling exists. |
| Search/paginated older data | **Not Implemented** | Limited bootstrap/history reads and local responder status filter only. |
| App-specific translations | **Not Implemented** | Delegates exist; application text is not localized. |
| Mobile admin/dispatcher interface | **Not Implemented**, apparently intentionally excluded | Login permits only resident/driver roles; admin/dispatcher website exists. Not automatically a required mobile feature. |

Direct emergency dialing and automatic dispatch are also **Not Implemented**. Current UI explicitly describes report submission for review; adding those behaviors would be a product change, not repair of an existing API connection.

## 11. API and Database Integration Requirements

### Verified endpoint-to-database map

All routes below are declared in `mdrrmo/routes/api.php` and registered by `mdrrmo/bootstrap/app.php`. Base path is `/api`; Flutter `API_URL` already includes it.

| HTTP / relative path | Flutter caller | Laravel action | Data operation |
|---|---|---|---|
| POST `/auth/mobile/login` | `AuthService.login` | `MobileAuthController::authenticate` | Reads role-specific account/hash; creates token. |
| POST `/auth/mobile/register` | `AuthService.register` | `MobileAuthController::register` | Reads cross-role email existence; creates `ResidentUser`. |
| GET `/auth/mobile/me` | `AuthService.getMe` (unused) | `MobileAuthController::me` | Returns authenticated account. |
| POST `/auth/mobile/logout` | `AuthService.logout` | `MobileAuthController::logout` | Deletes current personal access token. |
| GET `/resident/bootstrap` | `ResidentApi.fetchBootstrap` | `MobileResidentApiController::bootstrap` | Reads owner profile, categories, last 50 reports/schedules/notifications. |
| POST `/resident/reports` | `ResidentApi.submitReport` | `MobileResidentApiController::storeReport` | Creates report and notification, accepted residents only. |
| POST `/resident/schedules` | `ResidentApi.submitSchedule` | `MobileResidentApiController::storeSchedule` | Creates schedule and notification. |
| PATCH `/resident/notifications/{id}/read` | `ResidentApi.markRead` | `MobileResidentApiController::markRead` | Owner-scoped `read_at` update. |
| PATCH `/resident/notifications/read` | `ResidentApi.markAllRead` | `MobileResidentApiController::markAllRead` | Bulk owner-scoped unread update. |
| GET `/driver-responder/bootstrap` | `DriverApi.fetchBootstrap` | `MobileDriverApiController::bootstrap` | Reads driver/team/vehicle, first active assignment and incident types. |
| GET `/driver-responder/history` | `DriverApi.fetchHistory` | `MobileDriverApiController::history` | Up to 100 driver's resolved/invalid assigned reports. |
| GET `/driver-responder/incident-types` | `DriverApi.fetchIncidentTypes` (unused) | `MobileDriverApiController::incidentTypes` | Reads categories; bootstrap already supplies them. |
| PATCH `/driver-responder/assignments/{reportId}/status` | `DriverApi.updateAssignmentStatus` | `MobileDriverApiController::updateStatus` | Validates ownership/transition; updates vehicle, resolves report on completion. |
| PATCH `/driver-responder/availability` | `DriverApi.updateAvailability` | `MobileDriverApiController::updateAvailability` | Updates team vehicle with no active assignment. |
| PUT `/driver-responder/profile` | `DriverApi.updateProfile` | `MobileDriverApiController::updateProfile` | Updates driver identity/contact and team vehicle type/plate. |
| POST `/driver-responder/reports` | `DriverApi.submitReport` | `MobileDriverApiController::storeReport` | Creates pending report including JSON victim/contact details. |

Laravel also exposes `/driver-responder/assignments`, `/teams` and GET `/reports`; Flutter does not call them. Their presence does not supply multiple assignments, additional lists or live updates to the current app. They are not needed for the existing bootstrap requests to be real.

### Persistence and authorization

- Models: `ResidentUser` uses `residents`, `DriverResponderUser` uses `drivers`; `User` provides hashed passwords, role metadata and Sanctum tokens. Role accounts are separated through the domain migration, not only a shared `users.role` column.
- `ResidentUser::reports()` is a polymorphic owner relationship; `schedules()` uses `resident_id`. `EmergencyReport` relates incident type, reporter, team, driver and patient-care form; JSON patient data is cast as arrays.
- Primary tables: `incident_types`, `emergency_reports`, `service_schedules`, `resident_notifications`, `response_teams`, `team_members`, `vehicles`, `residents`, `drivers`, `personal_access_tokens`, and `account_id_sequences` for account ID allocation.
- Supporting website tables/models include hospitals, shifts, report forms and audit logs. Their existence does not imply mobile access.
- Relevant schema source: `mdrrmo/database/migrations/2026_10_26_110321_create_mddrmo_db.php`; token schema is in `2026_10_28_124052_create_personal_access_tokens_table.php`. The domain migration later separates account tables and removes/reworks initial shared-user relationships; do not infer final foreign keys from only its first table definitions.
- Mobile authenticated groups use `auth:sanctum` and role middleware. `RoleMiddleware` checks active account status. Resident notification writes and driver assignment writes include ownership checks.
- Database existence, migration execution, seeded incident types/team/vehicle records, issued driver accounts, accepted resident status and token validity must be verified in a separately authorized runtime check. No setup or query was performed here.

### CRUD coverage

| Resource | Create | Read | Update | Delete / cancel |
|---|---|---|---|---|
| Resident account | Implemented registration | Login/bootstrap/me service | No resident mobile edit | No mobile deletion |
| Emergency report (resident) | Implemented | Bootstrap/list | No resident mobile edit | No mobile withdrawal/delete |
| Emergency report (driver) | Implemented | Assigned current/history only | Assigned vehicle progression/resolution | No driver invalidation/delete UI |
| Schedule | Implemented | Bootstrap/request list | No mobile edit | No mobile cancel (website has it) |
| Resident notification | Created by server | Bootstrap | One/all read | No mobile deletion |
| Driver identity/team vehicle | No mobile creation | Bootstrap | Profile/availability implemented | No mobile removal |
| Trip telemetry/destination | No capture | No meaningful payload | No mobile update | Not applicable yet |
| Patient-care `ReportForm` | No Flutter operation | No Flutter operation | Website save only | No Flutter operation |

Missing delete operations are not automatically defects: emergency-record retention and permitted cancellation rules must be specified before adding them.

### Required contract/integration work

1. Restore source buildability before any end-to-end sign-off; then exercise login, both bootstraps and each mutation against a controlled test backend.
2. Standardize vehicle enum parsing and a canonical schedule time format across website, API and Flutter. Return explicit structured category/status/notification kinds rather than infer semantics from English text.
3. Add a refresh strategy and total unread counts. For push/realtime, define authorized mobile channels/device registration; the existing `dispatch` broadcast channel is dispatcher-only.
4. Expose mobile-authenticated, owner-scoped operations for schedule cancellation, detailed records, patient-care editing and GPS pings if these enter scope. Existing web endpoints use a different session/navigation contract and cannot simply be assumed to work with bearer tokens.
5. Define destination/trip events and metric schema/API representation. The inspected emergency report schema/payload does not provide destination, pickup event, duration or distance fields. Existing vehicle coordinates alone do not implement trip history.
6. Align accepted-resident checks, backend notification/audit effects, and vehicle transitions across web/mobile. Reuse the shared workflow rather than duplicating status writes.
7. Preserve reference/related-record identifiers in client models. Surface backend validation messages consistently, distinguish offline/timeouts/401/403/422, and add idempotency/reconciliation for ambiguous writes.
8. Use transactions for report/schedule + notification writes and driver + vehicle profile writes. Validate complete timestamps/slot rules and protect concurrent assignment/availability operations.

### Existing test evidence (source only)

`mdrrmo/tests/Feature/MobileApiTest.php` defines five tests for resident report persistence/owner isolation, schedule persistence/notification, driver progression to completion/history, profile update/emergency pending report, and pending resident registration. They have meaningful database assertions. They were **not run**, and they do not prove the Flutter parsers, UI, real token login, all authorization/error cases or release builds.

`test/resident_models_test.dart` contains one incident-name/style test. Its import reaches the invalid `resident_models.dart` import, so even this test requires the source blocker to be resolved. iOS/macOS `RunnerTests.swift` contain empty example tests.

## 12. Code Quality Issues

### Critical and high-impact findings

| ID / severity | Evidence | Impact / recommendation |
|---|---|---|
| CQ-01 **Critical** | `lib/data/resident_models.dart:3` imports `../../ui/kit.dart`. Resolved target is `mdrrmo_flutter/ui/kit.dart`, which does not exist. | Verified unresolved import; correct intended relationship to `lib/ui/kit.dart` in a future implementation task. Affects models/test and reachable app. |
| CQ-02 **Critical** | `lib/screens/resident/resident_app.dart:5` imports `../../../state/resident_state.dart`. Resolved target is `mdrrmo_flutter/state/resident_state.dart`, which does not exist. | Verified unresolved import; actual file is `lib/state/resident_state.dart`. |
| CQ-03 **High, runtime risk unverified** | Root uses `material_ui.MaterialApp`; most screens and `snack` use Flutter's Material library. Cached Forui also uses `material_ui`, whose `Theme`/Material widget classes are distinct source definitions. | Mixed inherited `Theme`, localization, Material and `ScaffoldMessenger` types can cause missing ancestors/theme mismatches or inconsistent rendering. Standardize a compatible Material family and test dialogs, snackbars, date/time pickers and themes. No runtime assertion failure is claimed without execution. |
| CQ-04 **High** | `DriverProfile.fromJson` accepts `fire_truck`/`rescue`; server returns `fire-truck`/`rescue-van` and other supported values. | Non-ambulance type displays as Ambulance and can be overwritten when saved. Centralize and round-trip-test enums. |
| CQ-05 **High** | States load only on construction/retry; no success-state refresh UI/timer/subscription. | Dispatcher assignments, incident resolution, schedule decisions and notifications remain stale for the active session. |
| CQ-06 **High** | `MobileDriverApiController::updateStatus` chooses first team vehicle without filtering by `assigned_report_id` or locking the checked records. `vehicleFor` also chooses first matching vehicle. | May mutate the wrong vehicle in multi-vehicle teams; check/update races exist. Website `DriverController::updateStatus` has stronger matching/locking. Reuse consistent selection and transactional workflow. |
| CQ-07 **High** | Mobile completion directly updates report status/resolved time instead of `EmergencyReportWorkflow::transition`. | Skips shared workflow's resident notification, report event and audit effects. Mobile can resolve a report from acknowledged status while shared workflow only permits resolved after dispatched. |
| CQ-08 **High** | Root manifest has no explicit INTERNET permission; debug/profile manifests have it. Android release uses debug signing. macOS entitlements lack outgoing `network.client`. | Release-network/signing readiness is incomplete. Final Android merged permissions and actual macOS execution remain unknown; audit release outputs before deployment. |
| CQ-09 **High** | Flutter API config/fallback use HTTP; no cleartext exception was found in authored Android main manifest, nor ATS exception in iOS plist. | Production transport is insecure and platform policies may block local HTTP; API connectivity on deployed targets is unknown. Use a tested HTTPS deployment/environment strategy. |

### Correctness, data integrity and lifecycle

- **CQ-10 — Time format:** `ScheduleRequest.fromJson` defaults to the date's midnight when time is not AM/PM; website `ResidentController::storeSchedule` validates `H:i`. Bootstrap can show wrong appointment times for website-origin data.
- **CQ-11 — Approval rules differ:** mobile report creation requires accepted registration; mobile schedule creation does not, while web schedule creation does. Flutter does not convey this difference or pending/declined approval.
- **CQ-12 — Non-atomic writes:** mobile report/schedule creation and notification insertion are separate writes; driver and vehicle edits are separate writes. A later failure can produce an error after the primary record was already saved. Retrying can duplicate reports/requests; no idempotency key exists.
- **CQ-13 — Strict bootstrap parsing:** unsupported report statuses/service labels or malformed list values can fail an entire resident load. Resident load mutates multiple state fields before parsing is complete; no immutable all-or-nothing result or request version prevents overlapping refresh races.
- **CQ-14 — False trip event labels:** details use `reported_at` as patient pickup time; destination/duration/distance are absent and resolution time is reused as arrival. Do not present report creation as measured transport activity.
- **CQ-15 — Empty initials crash:** `InitialsAvatar._initials` indexes `parts.first[0]`; an empty/whitespace name causes a range error. Empty names are possible in model defaults or malformed data.
- **CQ-16 — Async races:** login keyboard submission lacks an in-flight guard; emergency confirmation occurs before the guard is set; notification writes/logout have no busy guard. Shared FormPage cannot disable submit, although form-level checks suppress many duplicates.
- **CQ-17 — Stale/incomplete responder state:** completion clears assignment before history reload; a history failure then reports an operation error after server completion. `profile.status` is not synchronized by `advanceAssignment`. `saveProfile` can derive availability solely from vehicle status despite an active assignment.
- **CQ-18 — Status/presence assumptions:** unknown availability maps to dispatched; unknown priority maps High; unknown history status maps Invalid. Defaults can hide API contract drift. Administrative active statuses are shown as online presence.
- **CQ-19 — Lifecycle/refresh:** `_notify` prevents post-dispose notifications, but most pending operations still mutate disposed state; loads are not cancelled. Resident retry rebuilds the whole tab stack and can lose in-progress forms. No stale-response suppression exists.
- **CQ-20 — Timezone:** API timestamps can be UTC; format helpers display their components without consistent `.toLocal()` conversion. Grouping/report times can be incorrect for Asia/Manila; actual backend timezone is unknown. Relative times are recomputed only on rebuild and treat future timestamps as “Just now.”
- **CQ-21 — Form validation:** client/server max lengths differ; driver/emergency phone regex allows implausible strings made only from permitted punctuation/digits. Schedule accepts past time today and backend mobile time is merely a short string. Coordinate bounds are validated server-side but no municipality/service-area rule is enforced here.
- **CQ-22 — Onboarding/session:** first registration pops to role selection; valid tokens do not restore sessions; unsupported-role login can leave a saved token; selected account role is not updated to the returned role.

### Error handling and security

- **CQ-23 — Startup recovery:** `dotenv.load` and `AppPrefs.init` have no fallback/error screen. Missing asset or plugin initialization failure can stop before splash.
- **CQ-24 — HTTP error handling:** auth has 15-second timeouts/shape checks; Dio has 10-second connect/receive timeouts and an auth interceptor. There is no shared response interceptor for expired tokens or structured Laravel errors. Screens frequently render raw exception/Dio strings instead of safe, field-specific messages.
- **CQ-25 — Logout cleanup:** local token is deleted only after a successful server response. An already invalid/revoked token or network outage can prevent sign-out; no explicit local-only cleanup path exists.
- **CQ-26 — Client configuration exposure:** `.env` is declared as an asset and appears in existing build assets; `.gitignore` does not exclude it. This is safe only for public settings. No credential leak is asserted; repository history and deployed assets were not audited. The `DEBUG` environment key has no discovered application consumer.
- **CQ-27 — Token/rate policies:** `mdrrmo/config/sanctum.php` has null expiration; mobile login creates tokens without explicit expiry/abilities. No throttle middleware is attached to mobile login/register routes in the inspected route/bootstrap source. Fortify defines a login limiter separately, which does not establish that these custom mobile endpoints use it. Upstream limits are unknown.
- **CQ-28 — Availability authorization granularity:** server verifies active role and membership, but any matching driver can edit the selected shared team vehicle. Required organizational permission scope is unknown; confirm it and enforce the intended vehicle-level rules.
- **CQ-29 — Privacy/evidence:** patient and contact data are sent to Laravel but there is no persisted consent metadata, mobile privacy-policy view, or visible retention/account deletion workflow. These are observed gaps, not a legal-compliance determination.

### Organization, duplication and unused code

- **CQ-30 — Exact duplicate layouts:** `FormPage` and `FormGroup` are defined in both `lib/ui/form_page.dart` and `lib/screens/driver-responder/driver_form_screen.dart`. Registration uses the shared file; emergency imports another screen to obtain duplicates. Consolidation would remove divergent changes and screen-to-screen coupling.
- **CQ-31 — UI/domain coupling:** resident models import UI icons/colors, while `ui/kit.dart` imports responder models. JSON/domain models therefore require Flutter presentation code and are harder to test independently. A single 830-line `kit.dart` and large combined screen files mix many responsibilities.
- **CQ-32 — Duplicated transport/enums:** `http` and Dio repeat URL, timeouts, bearer/error logic. `DriverProfile.apiVehicleType` conflicts with `ResponderState._apiVehicleType`; two different centers are used across maps. Consolidate contracts before extending features.
- **CQ-33 — Unused members:** `AuthService.getMe`, `DriverApi.fetchIncidentTypes`, and `DriverProfile.apiVehicleType` have no callers. `NotificationKind.rate` has no parser path. Several predefined category values/styles are only used for matching or not selected directly; do not delete without checking intended use.
- **CQ-34 — Dependency hygiene:** `cupertino_icons` has no direct source use; `material_ui` is used directly but only transitively declared. No whole Dart screen file was found clearly unreachable from the navigation/import graph. `flutter_01.png` is unreferenced; generated/IDE directories are not automatically deletable “unused source.”
- **CQ-35 — Starter release metadata:** README/pubspec description, Android package/label, iOS/macOS naming and web manifest/icons retain starter values. Android actual ID is `com.example.mdrrmo_flutter`, while map requests use `ph.gov.mdrrmo.responder` as their user-agent identifier. Review actual distribution identifiers.
- **CQ-36 — Debug/lint cleanup:** splash prints account type; some helper `if` statements omit braces and API values use force casts/non-null assertions. These are source observations, not a fabricated analyzer report. `AppSelect` uses a managed initial value; programmatic selection updates should be tested rather than assumed controlled.

### Performance, accessibility and test gaps

- **CQ-37 — Eager construction:** long list comprehensions inside `ListView(children: ...)`, resident global bootstrap, broad `InheritedNotifier` rebuilds and `IndexedStack` create/rebuild more content than a paged/lazy feature would. Current server caps limit the impact; no profiler measurements were taken.
- **CQ-38 — Layout cost:** `RouteTimeline` uses `IntrinsicHeight` repeatedly in history lists. Test realistic list sizes and large text before optimizing.
- **CQ-39 — Map resilience:** no explicit tile-failure/offline UI or application-level offline cache; hidden preserved maps can consume memory/network resources. Actual plugin caching and offstage activity were not measured.
- **CQ-40 — Accessibility/responsiveness:** role cards, nav, pins/actions and the SOS button include some semantics; SOS animation respects reduced motion. Fixed segmented rows, the raised navbar, fixed map heights, dialog actions and details header can overflow on small screens/large text. Profile sheet is not scrollable. Actual visual/accessibility behavior is unknown.
- **CQ-41 — Sparse validation coverage:** one Dart model test, no discovered widget/state/API/integration test suite, no Flutter CI configuration discovered in the project inventory. Native example tests contain no assertions. Backend tests do not exercise Flutter parsing or rendering.

## 13. Recommended Improvements

1. **Establish a buildable baseline:** repair the two import paths and resolve the Material/Forui compatibility strategy. Run analyzer and the existing test only when changes/generated outputs are authorized. Check light/dark themes, dialogs, snackbars and pickers on supported targets.
2. **Fix contract corruption before adding screens:** centralize vehicle enums, schedule time serialization and status handling; preserve server IDs/references. Add focused regression coverage for non-ambulance round trips, website-created times and unknown payload values.
3. **Unify backend workflows:** select/lock the actual assigned vehicle and reuse shared report transitions, audit, notifications and authorization. Make report+notification and profile+vehicle writes atomic.
4. **Make current information refreshable:** add explicit refresh and lifecycle reload first, then evaluate authorized polling or push/realtime. Model loading, stale data, empty results, authorization failure and retry independently per feature.
5. **Complete account lifecycle:** restore valid sessions, clear invalid tokens, align pending-resident rules and first-registration handoff, and normalize safe validation errors.
6. **Complete existing record journeys:** retain created references, expose report details, schedule notes/cancellation where permitted, and related-notification navigation. Add pagination rather than silently treating limited bootstrap data as complete history.
7. **Remove false data semantics:** show unknown trip/presence information honestly until recorded event/destination/presence contracts exist. Do not fabricate telemetry from report timestamps.
8. **Simplify ownership:** share one form layout, separate model parsing from presentation, split the UI kit by responsibility and consolidate HTTP/auth behavior. Keep public config separate from secrets.
9. **Validate deployment:** HTTPS, release manifest permissions/entitlements, signing, app identifiers, supported SDK/toolchain and target-device storage/network behavior.
10. **Expand tests around risk:** prioritize parser corruption, role/owner isolation, concurrency, session expiry and form submission outcomes over tests that only mirror static widget implementation.

No proposed improvement was implemented as part of this audit.

## 14. Development Roadmap

### High Priority

1. Fix CQ-01/CQ-02 unresolved imports and establish reproducible supported Flutter/Dart versions.
2. Resolve CQ-03 Material-family compatibility; validate startup, navigation, forms, snackbars and pickers.
3. Fix vehicle-type round-trip corruption and schedule time-format incompatibility.
4. Correct assigned-vehicle selection/concurrency; align mobile completion with shared notifications/audits/workflow rules.
5. Align approval restrictions; prevent ambiguous duplicate submissions and make related backend writes atomic.
6. Add session restoration, expired-token handling and reliable local logout cleanup.
7. Add refresh/new-assignment discovery for active responders and fresh report/schedule/notification state for residents.
8. Validate HTTPS and release connectivity/signing; add targeted Dart/backend/integration checks for these fixes.

**Exit criteria:** source builds; both account roles complete verified API-backed workflows; profile values round-trip; refresh discovers dispatcher changes; completion has consistent persisted side effects; failed/expired sessions recover safely.

### Medium Priority

1. Add per-screen loading/error/retry, meaningful empty states and backend validation mapping.
2. Add paginated report/schedule/notification/history reads and correct total unread counts.
3. Add permitted record details, schedule notes/edit/cancel and notification deep links.
4. Retain submitted report references and provide driver-authored report visibility.
5. Define and implement trip/destination/event data; correct pickup/arrival semantics immediately.
6. Add phone actions/contact payload, actual presence if required, and assignment-centered maps.
7. Expose mobile patient-care/GPS endpoints only after ownership and product scope are defined.
8. Consolidate layouts, enum mapping, network/session logic and model/presentation responsibilities.
9. Test timezone conversion, mixed web/mobile schedules, accessibility and large-text/small-screen behavior.

**Exit criteria:** current records remain accessible and understandable; old records are reachable; permitted follow-up actions work; UI fields correspond to authoritative data.

### Low Priority

1. Evaluate optional push delivery, offline drafts/outbox, attachments and ratings against product needs.
2. Add translations and complete public-facing metadata/documentation.
3. Improve logo assets and tune long-list/map rebuild behavior based on profiling.
4. Review unused members/dependencies and consolidate obsolete examples during an authorized cleanup.
5. Expand CI/device/release coverage after the core workflows have reliable tests.

**Exit criteria:** optional features have explicit scope and acceptance criteria; polish/performance work is supported by measured or observed needs.

## 15. Priority Task Checklist

Items checked below were completed across the implementation batches. Unchecked items remain in the backlog; the original audit remains a historical baseline.

- [x] Correct the import in `lib/data/resident_models.dart` and verify its target exists.
- [x] Correct the state import in `lib/screens/resident/resident_app.dart` and verify its target exists.
- [x] Establish a compatible Forui/Material import strategy and declare every directly used dependency explicitly.
- [x] Run analyzer and the existing Dart test in an authorized implementation session; record actual results.
- [ ] Verify launch, both role flows, navigation, dialog, snackbar and date/time picker rendering.
- [x] Round-trip all five server vehicle types through `DriverProfile` without changing values.
- [x] Parse and display both existing website schedule times and Flutter-submitted times correctly.
- [x] Align client/server time, name, phone and field-length validation.
- [x] Add pending/declined resident representation and consistent server approval checks.
- [x] Route successful first-launch registration to a clear sign-in next step.
- [x] Wire `AuthService.getMe` into startup session restoration.
- [x] Handle 401/expired/revoked tokens centrally and clear local session safely on logout.
- [x] Guard login keyboard submission, emergency confirmation, notification writes and logout against concurrent execution.
- [x] Select the vehicle actually assigned to an incident and lock transition reads/writes.
- [x] Route mobile report completion through the shared workflow and verify resident notification/audit/event effects.
- [x] Make report/schedule+notification and driver+vehicle edits transactional.
- [x] Define idempotency/reconciliation behavior for timeouts after a successful server write.
- [x] Add a visible refresh/lifecycle reload path for both modules.
- [x] Verify a newly assigned report appears without requiring logout or an error-state retry.
- [x] Separate responder history loading/error from empty results.
- [x] Keep availability/profile status consistent after every assignment transition.
- [x] Retain server report references and driver emergency submission results in client state.
- [x] Add page/cursor queries for older report/schedule/notification/dispatch records.
- [x] Return total unread count separately from the loaded notification page.
- [x] Preserve notification related IDs and add authorized record navigation.
- [x] Add schedule notes and permitted cancellation with an owner-scoped mobile endpoint.
- [x] Define destination/pickup/arrival/duration/distance contracts before displaying measured trip data.
- [x] Remove the assumption that `reported_at` means patient pickup time.
- [x] Add team contact payload and dialing only if calling belongs in scope.
- [x] Add map tile-error feedback and recenter/fit to the assigned incident.
- [x] Add assigned-driver mobile patient-care viewing/editing. GPS/background tracking was subsequently added in optional item 16.
- [x] Consolidate duplicate `FormPage`/`FormGroup` implementations.
- [x] Make initials handling safe for empty names and normalize timezone presentation.
- [ ] **Deferred by user:** validate HTTP-to-HTTPS deployment, Android merged release permissions and Apple entitlements/network behavior.
- [ ] **Deferred by user:** configure release signing. Starter distribution metadata remains a separate lower-priority task.
- [x] Review token expiry/rate limiting and ensure bundled `.env` contains public settings only.
- [ ] Complete physical-device/end-to-end verification when authorized. Automated parser/state/API/widget coverage is implemented; 56 Flutter and 84 backend tests pass.
- [ ] Perform supported-target accessibility, small-screen and large-text checks.
- [ ] Update the starter README with architecture, environment and verification instructions.

- [x] Add owner-scoped resident report and schedule details and pending-only edits.
- [x] Persist report withdrawal metadata without erasing emergency records.
- [x] Add driver-authored pending report history and persistent submission receipts.
- [x] Add responder inbox and multiple-assignment selection.
- [x] Add resident profile/avatar editing and private avatar serving.
- [x] Add current-password changes and rate-limited email-code password recovery.
- [x] Persist account deletion requests/cancellation with explicit retention information.
- [x] Record actual trip events/destination and clearly label manually reported distance.
- [x] Replace administrative online assumptions with observed mobile activity.
- [x] Consume server incident colors and add remaining empty states.
- [x] Apply the medium-priority additive migration to local PostgreSQL and run regression checks.

- [x] Implement optional item 16: automatic assigned-vehicle GPS updates with OS permission checks and Android/iOS background mode, replacing the original manual sharing flow.
- [x] Implement optional item 23: server-side search/date filters before pagination.
- [x] Implement optional item 25: scoped mobile admin/dispatcher sign-in and operational interfaces.
- [x] Implement optional item 26: staff-controlled automatic dispatch, off by default, with commit-time allocation and retry command.
- [x] Apply the optional-feature additive migration to local PostgreSQL; run 66 Flutter and 101 backend tests.
- [ ] During authorized deployment setup, run the Laravel scheduler for unattended automatic-dispatch retries.
- [ ] During authorized physical-device verification, validate GPS permission/service behavior, background delivery and native plugin linking.

### Documentation coverage verification

- [x] All 31 discovered `lib/` Dart files inventoried, including both state scopes and all API/auth services.
- [x] Four entry/auth screens, both module containers/shells, five resident tabs, resident profile sheet, and five responder content/form/detail screens covered.
- [x] Every discovered button/action category traced to its callback, local-only behavior, API request or absent implementation.
- [x] Every currently called Flutter endpoint matched to Laravel route/controller and persistence code.
- [x] Placeholder/static data separated from actual server-backed lists and writes.
- [x] Missing mobile workflows separated from website features and optional product extensions.
- [x] All five requested status categories used, with source evidence and runtime verification limits stated.
- [x] Build blockers, validation, errors/loading, security, performance, duplication, unused candidates and test gaps documented.
- [x] High/medium/low roadmap and sequential actionable checklist included.
- [x] No existing Dart/UI/backend/configuration/dependency files changed; only this Markdown document created.
