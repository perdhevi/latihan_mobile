# Fitness Mobile

An open-source, offline-first fitness tracking application for iOS and Android, built with Flutter.

`fitness-mobile` provides the core fitness experience for the Fitness Platform and is designed to work as a fully functional standalone application without requiring an account, cloud service, or commercial backend.

## Project Goals

The project aims to provide a clean, production-quality foundation for tracking personal fitness activity while remaining useful as an independent open-source application.

The public fitness domain includes:

- Exercise library
- Workout tracking
- Sets, repetitions, and weight
- Duration and distance tracking
- Workout history
- Personal records
- Progress tracking
- Body measurements
- Offline storage
- Optional cloud synchronization

The application is designed around an **offline-first** model. Recording and reviewing workouts must never depend on network connectivity.

## Architecture

Fitness Mobile is part of a larger open-core fitness platform.

```text
              Official Mobile App
                      |
        +-------------+-------------+
        |                           |
 fitness-mobile             fitness-commercial
 Public Flutter              Private Flutter
        |
        +---------- HTTPS ---------+
                    |
              API Gateway
               /       \
              v         v
       fitness-api   gym-platform
        Public Go     Private Go
```

The open-source version requires only `fitness-mobile`.

`fitness-api` can optionally provide cloud storage and synchronization.

Commercial functionality such as gym memberships, subscriptions, advertising, coach relationships, and booking is intentionally kept outside this repository.

## Open-Core Design

The project follows a simple rule:

> Fitness functionality is open source. Commercial relationships and business rules are not.

This repository must never depend on the private `fitness-commercial` repository.

Instead, optional functionality is exposed through interfaces.

For example:

```dart
abstract interface class CommercialExtension {
  bool get isAvailable;

  Future<void> initialize();
}
```

The open-source application provides a no-op implementation.

Private distributions may provide another implementation through dependency injection.

This keeps the OSS application independently buildable and usable.

## Project Structure

The application uses feature-oriented organization.

```text
lib/
├── app/
│   └── app.dart
│
├── core/
│   ├── extensions/
│   ├── networking/
│   ├── storage/
│   └── sync/
│
├── features/
│   ├── exercises/
│   ├── workouts/
│   ├── history/
│   ├── progress/
│   └── measurements/
│
└── main.dart
```

Features may use `data`, `domain`, and `presentation` layers when their complexity justifies the separation.

The project deliberately avoids introducing layers or abstractions that do not yet solve a real problem.

## Offline First

Local storage is the source of truth for the mobile application.

Users should be able to:

1. Browse exercises.
2. Start a workout.
3. Record sets and repetitions.
4. Complete a workout.
5. Review workout history.

All without an internet connection or user account.

Cloud synchronization is an optional enhancement.

Records use client-generated identifiers suitable for eventual synchronization with `fitness-api`.

Synchronization will account for:

- Client-generated UUIDs
- Creation and modification timestamps
- Deleted records
- Retry handling
- Idempotency
- Duplicate prevention
- Conflict detection

## Backend

Cloud synchronization is provided by the separate open-source `fitness-api` project.

The backend is built with:

- Go
- PostgreSQL
- REST
- OpenAPI
- Docker

Using the backend is optional.

The mobile application must remain functional without it.

## Commercial Extensions

Commercial features are intentionally excluded from this repository.

Examples include:

- Gym memberships
- Membership plans
- Coach-athlete relationships
- Scheduling and booking
- Billing
- Subscriptions
- Entitlements
- Advertising implementations

Commercial builds can integrate these capabilities through extension interfaces exposed by the public application.

Authoritative commercial rules must always be enforced server-side. The Flutter application is treated as an untrusted client.

## Development

### Requirements

Install:

- Flutter SDK
- Dart SDK
- Android Studio and/or Android SDK
- Xcode for iOS development on macOS

Verify your environment:

```bash
flutter doctor
```

Clone the project:

```bash
git clone https://github.com/<your-username>/fitness-mobile.git
cd fitness-mobile
```

Install dependencies:

```bash
flutter pub get
```

Run the application:

```bash
flutter run
```

## Testing

Run all tests:

```bash
flutter test
```

Run static analysis:

```bash
flutter analyze
```

Format the project:

```bash
dart format .
```

## Development Roadmap

Initial development focuses on building the open fitness foundation.

```text
Exercise Library
      ↓
Local Exercise Storage
      ↓
Exercise Library UI
      ↓
Workout Recording
      ↓
Workout History
      ↓
Progress Tracking
      ↓
fitness-api Integration
      ↓
Cloud Synchronization
      ↓
Authentication
```

The first vertical slice will implement the exercise library from local storage through the Flutter UI.

Cloud-backed exercises will then be introduced through `fitness-api` while preserving offline operation.

## Principles

Development follows a few core principles:

- Offline functionality comes first.
- The OSS application must remain independently useful.
- Fitness functionality belongs in the public repository.
- Commercial business rules stay outside the public repository.
- Flutter clients are never trusted with authoritative business decisions.
- Prefer simple implementations over premature abstraction.
- Prefer explicit Dart code over framework magic.
- Design APIs and storage formats with synchronization in mind.
- Add abstractions when they solve an existing problem, not a hypothetical one.
- Keep the project easy to build, test, and understand.

## Status

🚧 **Early Development**

The project is currently establishing its architecture and first fitness-domain vertical slices.

The initial development target is:

**Exercise Library → Local Storage → Flutter UI**

Followed by integration with the Go `fitness-api`.

## Contributing

Issues, discussions, bug reports, and pull requests are welcome.

Before proposing major architectural changes, please open an issue or discussion describing the problem the change is intended to solve.

## License

This project is open source.

See [LICENSE](LICENSE) for details.
## Workout sessions

The home screen now shows locally saved workout history, newest first. Choose
**New session**, set a name and date, and add any number of exercises. Strength
exercises record repetitions and weight (0 kg for bodyweight) for each set.
Cardio exercises record minutes and an optional average heart rate.
Exercises can be edited or removed before saving. Tap a saved session to see
its full training details. The exercise library remains accessible from the
home screen toolbar.

Saved sessions persist on this device in a local SQLite database and can be
synchronized with the Go server (see Synchronization below). Unsaved sessions are not restored after closing the app.
Run `flutter test` and `flutter analyze` to verify this flow.

## Dashboard, plans and profile

The FitTrack dashboard shows real weekly session/set/cardio totals, recent
completed sessions, and five destinations: start/resume, previous sessions,
exercise ideas, Coach / Plan, and My profile.

Active sessions persist locally when activities are added, edited or removed.
Finish a session to add it to history. Plans are reusable: choose one when
starting a session and its exercises are snapshotted as that session's targets,
separate from the logged results and unaffected by later plan edits. Session
details show planned versus logged activities. Profile measurements support
weight (kg), height (cm), body fat (%), waist/chest/hip circumference (cm),
dated history and changes from the first measurement. Unsaved activity and
measurement forms are not persisted.

### Local database

Data is stored in SQLite through [drift](https://drift.simonbinder.eu)
(`lib/core/database.dart`), in a database named `latihan`. Tables, units and
bounds follow the Go API's OpenAPI contract: `profiles`, `measurements`,
`plans` and `sessions`. A plan or session keeps its exercises as a JSON column
in the contract's shape (`sets` of `repetitions`/`weight_kg`, `minutes`,
`avg_bpm`), because the API also replaces them as a whole. Every row records
`created_at` and `updated_at` for future synchronization.

After changing a table, regenerate `database.g.dart` and, once the app has
shipped, raise `schemaVersion` and add a migration:

```sh
dart run build_runner build
```

### Export

**Profile → Export my data** writes everything on the device to
`latihan-export-<date>.json` and opens the system share sheet to save or send
it. The document is laid out like the API's account export: `format`
(`latihan-mobile-export/1`), `exported_at`, `user`, `measurements`, `plans`,
`sessions`, plus `active_session` for a workout in progress. It contains local
data only; cloud data is not included.

### Exercise idea feed

Configure a server feed at build time:

```sh
flutter run --dart-define=EXERCISE_IDEAS_URL=https://your-server.example/api/v1/exercise-ideas
```

The endpoint must return a JSON array, or an object with an `items` array:

```json
{"items":[{"name":"Squat","category":"strength","tips":"Movement guidance supplied by your server.","video_url":"https://your-server.example/videos/squat.mp4"}]}
```

`description` is accepted as a fallback for `tips`. Videos are loaded only when
the user taps Watch movement. Use HTTPS URLs compatible with the platform video
player (e.g. MP4); web deployments also need appropriate server CORS headers.
The existing Go exercise catalog can supply names/descriptions but does not yet
provide video URLs. No feed or media service is deployed by this change. Without
a configured endpoint, Exercise ideas shows an explicit disconnected state.
Workouts, plans and measurements remain available offline.

## Go account integration

Open **Profile → Cloud account** to sign in or register with the Go server's
built-in JWT provider. New accounts are prompted to create a cloud display name.
The screen shows completed cloud sessions, including repetitions, weights,
cardio minutes and BPM, with refresh and cursor pagination. Access tokens refresh
automatically and the session is kept across restarts (see Synchronization).
External identity-provider sign-in is not yet implemented.

Enter the base URL ending in `/api/v1/`, or set its initial value at build time:

```sh
flutter run --dart-define=FITNESS_API_URL=http://10.0.2.2:8080/api/v1/
```

`10.0.2.2` addresses the host from the Android emulator. Android debug builds
allow HTTP for local development; use HTTPS for release builds and real accounts.
For physical devices, use a reachable server address; the Go Compose stack binds
to localhost by default. Browser builds require server CORS configuration.

### Synchronization

Signed in under **Profile → Cloud account**, the local database synchronizes
with the Go server. The device stays the source of truth and works offline; a
connection is needed only while a sync runs.

- **When:** automatically when the app opens, when it returns to the foreground
  (at most once a minute), and 5 seconds after you finish a session or save or
  delete a plan, measurement or your name. **Sync now** runs it on demand.
  Editing the session in progress does not trigger one; it is never synced.
- **Staying signed in:** the server URL and refresh token are kept in the
  platform keystore (`flutter_secure_storage`); the short-lived access token is
  fetched again as needed and never stored. Signing out revokes the token and
  forgets it but keeps your data. If the server ends the session you are signed
  out with a message; if the app starts offline you stay signed in and it syncs
  later.
- **Automatic runs never interrupt you.** A problem (offline, a rejected record,
  a different account) is shown on the Cloud account screen; nothing is lost.

- **Order:** profile, plans, sessions, measurements, then queued deletions.
- **IDs:** the server issues every ID and rejects client ones, so the table
  `sync_links` maps each local row to its server record. Records first seen on
  the server keep the server's ID locally.
- **Changes:** a row is unsynced when its `updated_at` differs from the one
  recorded at the last sync. Unsynced rows are created (`POST` with an
  `Idempotency-Key`, so a retry after a lost response never duplicates) or
  replaced (`PUT` with `If-Match`). The API has no change feed, so each sync
  lists every collection and compares `updated_at`.
- **Conflicts:** a record changed on both sides keeps the more recently updated
  version. Local edits to a record deleted on the server bring it back.
- **Deletions:** deleting a synced plan or measurement queues the server record
  in `pending_deletes`. A plan that server sessions still use answers 409 and is
  retried on the next sync.
- **Plans in use:** the server freezes a plan's exercises once sessions use it
  (`plan_in_use`); renames still apply. An edit to the exercises is uploaded as
  a new plan and the old one stays for its sessions. Other devices that already
  had the old plan will also receive the new one.
- **Plan links:** a session's `plan_exercise_id` is re-pointed at the matching
  entry of the server's current copy of the plan; if the plan has since
  changed so no entry matches, the link is left out. The server also builds the
  session's plan snapshot itself, from the plan as it is at upload time.
- **Not synced:** the session in progress (the API has no such concept).
- **One account per device.** Syncing with a different account is refused so
  one person's data is never uploaded into another's.
- **Failures:** a record the server rejects is listed and retried next time; a
  connection or authorization error stops the sync and is safe to repeat.

Tests: `test/sync_service_test.dart` runs against a fake server that models the
API's behaviour. `test/sync_live_test.dart` runs the same flow against a real
server and is skipped unless you pass it a URL (it registers a throwaway account):

```sh
flutter test test/sync_live_test.dart --dart-define=SYNC_LIVE_URL=http://localhost:8080/api/v1/
```
