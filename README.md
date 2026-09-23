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