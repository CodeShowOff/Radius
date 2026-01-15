# Radius - Flutter Project Structure

## Folder Structure Overview

```
lib/
├── main.dart                          # App entry point
├── app.dart                           # Root widget with providers & routing
│
├── core/                              # Shared utilities & infrastructure
│   ├── constants/
│   │   └── app_constants.dart         # Global constants & configuration
│   ├── di/
│   │   ├── injection.dart             # Dependency injection setup
│   │   └── injection.config.dart      # Generated DI configuration
│   ├── error/
│   │   ├── exceptions.dart            # Custom exception classes
│   │   └── failures.dart              # Failure types for error handling
│   ├── router/
│   │   ├── app_router.dart            # GoRouter configuration
│   │   └── routes.dart                # Route path constants
│   ├── services/
│   │   ├── bluetooth/
│   │   │   └── i_ble_service.dart     # BLE service interface
│   │   ├── cache/
│   │   │   └── i_local_cache_service.dart
│   │   └── firebase/
│   │       ├── i_firebase_auth_service.dart
│   │       └── i_firestore_service.dart
│   ├── theme/
│   │   └── app_theme.dart             # Light/dark theme configuration
│   └── usecases/
│       └── usecase.dart               # Base use case class
│
├── features/                          # Feature modules (Clean Architecture)
│   ├── auth/
│   │   ├── data/                      # (To be implemented)
│   │   │   ├── datasources/
│   │   │   ├── models/
│   │   │   └── repositories/
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   │   └── user.dart
│   │   │   ├── repositories/
│   │   │   │   └── i_auth_repository.dart
│   │   │   └── usecases/              # (To be implemented)
│   │   └── presentation/
│   │       ├── bloc/
│   │       │   ├── auth_bloc.dart
│   │       │   ├── auth_event.dart
│   │       │   └── auth_state.dart
│   │       ├── pages/
│   │       │   ├── login_page.dart
│   │       │   └── register_page.dart
│   │       └── widgets/               # (To be implemented)
│   │
│   ├── home/
│   │   └── presentation/
│   │       └── pages/
│   │           └── home_page.dart
│   │
│   ├── profile/
│   │   ├── domain/
│   │   │   └── repositories/
│   │   │       └── i_user_repository.dart
│   │   └── presentation/
│   │       └── pages/
│   │           └── profile_page.dart
│   │
│   ├── proximity/
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   │   ├── nearby_user.dart
│   │   │   │   └── proximity_event.dart
│   │   │   └── repositories/
│   │   │       └── i_proximity_repository.dart
│   │   └── presentation/
│   │       ├── bloc/                  # (To be implemented)
│   │       └── pages/
│   │           └── nearby_page.dart
│   │
│   └── splash/
│       └── presentation/
│           └── pages/
│               └── splash_page.dart
│
test/                                  # Unit & widget tests (To be implemented)
│
android/                               # Android native project
ios/                                   # iOS native project
```

## Purpose of Each Folder

### `lib/core/` - Core Module
Shared code used across all features.

| Folder | Purpose |
|--------|---------|
| `constants/` | App-wide constants, config values, Firestore paths, BLE UUIDs |
| `di/` | Dependency injection setup using get_it & injectable |
| `error/` | Exception and Failure classes for error handling |
| `router/` | Navigation configuration using GoRouter |
| `services/` | Interface definitions for external services (Firebase, BLE, Cache) |
| `theme/` | Material theme configuration (colors, typography, shapes) |
| `usecases/` | Base use case class for consistent business logic pattern |

### `lib/features/` - Feature Modules
Each feature follows Clean Architecture layers:

```
feature/
├── data/           # Data layer (implementations)
│   ├── datasources/   # Remote & local data sources
│   ├── models/        # Data transfer objects (DTOs)
│   └── repositories/  # Repository implementations
│
├── domain/         # Domain layer (business logic)
│   ├── entities/      # Business entities (pure Dart)
│   ├── repositories/  # Repository interfaces
│   └── usecases/      # Business logic use cases
│
└── presentation/   # Presentation layer (UI)
    ├── bloc/          # BLoC/Cubit state management
    ├── pages/         # Full-screen page widgets
    └── widgets/       # Reusable feature-specific widgets
```

### Feature Breakdown

| Feature | Purpose |
|---------|---------|
| `auth/` | User authentication (sign in, register, sign out) |
| `home/` | Main dashboard after login |
| `profile/` | User profile management |
| `proximity/` | BLE scanning & nearby user detection |
| `splash/` | Initial loading & auth check screen |

## Key Files

| File | Purpose |
|------|---------|
| `main.dart` | Entry point; initializes Hive, DI, Firebase |
| `app.dart` | Root widget; sets up BlocProviders, theme, router |
| `app_router.dart` | All route definitions & navigation guards |
| `app_theme.dart` | Light/dark theme with brand colors |
| `injection.dart` | Registers all dependencies in GetIt |
| `failures.dart` | Typed failure classes for error handling |
| `i_ble_service.dart` | BLE scanning/advertising contract |
| `i_auth_repository.dart` | Auth operations contract |

## Architecture Flow

```
UI → BLoC → UseCase → Repository (Interface) → DataSource → External Service
                              ↓
                     Repository (Implementation)
```

## Next Steps

1. **Configure Firebase** - Add firebase_core, firebase_auth, cloud_firestore
2. **Implement BLE Service** - Add flutter_blue_plus, permission_handler
3. **Implement Repositories** - Connect interfaces to actual services
4. **Add Use Cases** - Business logic for each feature
5. **Complete UI** - Add remaining widgets and screens
