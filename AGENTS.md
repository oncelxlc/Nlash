# Repository Guidelines

## Project Structure & Module Organization

Nlash is a HarmonyOS VPN application built with ArkTS and a C++ native bridge (`proxy_core`). The project consists of two modules:

### `entry/` — HAP Module (Main Application)

`pages/` contains `@Entry` pages; `view/` contains business `@Component` views and their child components; `components/` contains reusable presentation components. Domain types live in singular `model/`, shared values in `constants/`, and formatting, validation and calculation helpers in `utils/`. Keep existing `stores/`, `services/`, `repository/` and `navigation/` responsibilities; do not add a parallel ViewModel layer just for naming consistency. Models must not import constants, utilities or services.

| Path | Purpose |
|---|---|
| `entry/src/main/ets/pages/Index.ets` | Root page; responsive navigation shell (side/bottom nav), foldable-device aware |
| `entry/src/main/ets/view/DashboardPage.ets` | VPN dashboard — composes separate RuntimeSpeedCard, RuntimeTrafficCard and RuntimeStatusCard business components |
| `entry/src/main/ets/view/ConfigurationPage.ets` | Subscription/Profile management — add, validate, select, update, rename and delete |
| `entry/src/main/ets/view/` | Six primary business views plus the navigation base and dashboard cards |
| `entry/src/main/ets/components/EmptyStateCard.ets` | Shared title/description card for Requests and Connections |
| `entry/src/main/ets/components/PlaceholderPage.ets` | Retained generic placeholder component |
| `entry/src/main/ets/entryability/EntryAbility.ets` | UIAbility entry; initializes VPN, Profile, runtime and settings stores on `onCreate` |
| `entry/src/main/ets/entrybackupability/EntryBackupAbility.ets` | `BackupExtensionAbility` stubs for onBackup/onRestore |
| `entry/src/main/ets/vpnextension/ProxyVpnAbility.ets` | `VpnExtensionAbility` — establishes VPN, reads active Profile from Preferences and runs the Core/TUN/Protect lifecycle |
| `entry/src/main/ets/services/VpnService.ets` | VPN lifecycle orchestrator (start/stop with async-queuing, state broadcast via `EventHub`) |
| `entry/src/main/ets/services/SubscriptionService.ets` | Transactional subscription download, temporary-file Core validation and rollback-safe persistence |
| `entry/src/main/ets/stores/ProfileStore.ets` | UI-facing Profile state and serialized profile operations |
| `entry/src/main/ets/repository/ProfileRepository.ets` | S2 RDB persistence for Profile metadata |
| `entry/src/main/ets/repository/PreferenceRepository.ets` | Preferences persistence for the active Profile pointer |
| `entry/src/main/ets/model/ResponsiveModels.ets` | Responsive size class and metrics types |
| `entry/src/main/ets/constants/ResponsiveConstants.ets` | Compact, medium and expanded page/card spacing |
| `entry/src/main/ets/utils/ResponsiveUtils.ets` | Shared width conversion, breakpoint resolution and card height calculation |
| `entry/src/main/ets/services/VpnStatePublisher.ets` | Thin helper to emit typed `VpnStateEvent` on `applicationContext.eventHub` |
| `entry/src/main/ets/model/VpnModels.ets` | VPN state enums, events and listener types; helpers and shared values live in VpnUtils and VpnConstants |
| `entry/src/main/ets/model/NavigationModels.ets` | `AppPage` enum (6 pages) and `NavigationLayout` enum; navigation lists and resolution live in NavigationConstants and NavigationUtils |

**Navigation layout rules** (`resolveNavigationLayout`):
- Foldable + expanded + fullscreen/maximized → **Side** nav (all 6 pages)
- Foldable + expanded + floating/split-screen window → folded-style **Bottom** nav
- Foldable + folded + portrait → **Bottom** nav (DASHBOARD, PROXY, CONFIGURATION, SETTINGS)
- Non-foldable → **Bottom** nav, including wide windows
- REQUESTS and CONNECTIONS appear only in side nav; layout changes preserve the selected route

### `proxy_core/` — Native HAR/HSP Module

| Path | Purpose |
|---|---|
| `proxy_core/src/main/ets/index.ets` | ArkTS façade for version, validate/start/stop/state and sanitized Core events |
| `proxy_core/src/main/cpp/napi_init.cpp` | N-API module registration and async Core bridge |
| `proxy_core/src/main/cpp/prebuilt/arm64-v8a/` | Pinned Go/Mihomo c-shared `libnlash_core.so` and generated header |
| `proxy_core/src/main/cpp/CMakeLists.txt` | CMake build (C++17, links `libace_napi.z.so`, `libhilog_ndk.z.so`) |

### `native-core/` — Go c-shared Core

`native-core` pins Go/Mihomo metadata, builds the AArch64 c-shared Core with OHOS clang/musl, and synchronizes it into `proxy_core`. It owns config validation, Mihomo lifecycle, external TUN FD use and the Protect Channel client.

### Resources & Configuration

| Path | Purpose |
|---|---|
| `AppScope/app.json5` | Bundle name `com.zhexian.nlash`, version `1.0.0` |
| `AppScope/resources/base/element/string.json` | App name label |
| `entry/src/main/module.json5` | Declares `EntryAbility`, `ProxyVpnAbility` (type: `vpn`), `EntryBackupAbility`; network permissions |
| `entry/src/main/resources/base/element/string.json` | Chinese UI strings (仪表盘, 代理, 配置, etc.) |
| `entry/src/main/resources/base/element/color.json` | Light theme colors (background, card, nav, content) |
| `entry/src/main/resources/dark/element/color.json` | Dark theme color overrides |
| `entry/src/main/resources/base/profile/main_pages.json` | Page routing — only `pages/Index` registered |
| `entry/src/main/resources/base/profile/backup_config.json` | Backup extension configuration |

## Build, Test, and Development Commands

No Hvigor wrapper is committed, so use DevEco Studio's bundled tools (or add them to `PATH`). Set `DEVECO_SDK_HOME` to the DevEco Studio `sdk` directory before invoking Hvigor. From the repository root:

- `ohpm install` — restore dependencies from `oh-package-lock.json5`.
- `hvigor clean` — remove generated module build output.
- `hvigor assembleHap` — build the default HAP, including `proxy_core` through CMake.
- `hvigor test` — run the configured Hypium unit-test task.
- `native-core/build-ohos.ps1` — build the pinned minimal Go c-shared probe and sync the arm64 prebuilt library.

Use DevEco Studio's **Run** action for `ohosTest` suites because they require an emulator or HarmonyOS device. Never commit machine-specific `local.properties`, signing files, or generated `build/`, `.hvigor/`, and `oh_modules/` directories.

**Dependency note:** `oh-package.json5` declares `@ohos/hypium` and `@ohos/hamock` as devDependencies. No `@kit.*` runtime dependencies need explicit declaration — they are resolved by `compileSdk` in `build-profile.json5`.

## Coding Style & Naming Conventions

Follow existing ArkTS style: two-space indentation, semicolons, single quotes, explicit public API types, `PascalCase` for classes/types/components, `camelCase` for functions and variables, and `UPPER_SNAKE_CASE` for constants. Keep services focused and expose shared state through typed models. C++ targets C++17; use four-space indentation, `PascalCase` functions, and the `nlash` namespace. Run the DevEco linter using `code-linter.json5`; native diagnostics are configured in `.clang-tidy` and `.clangd`.

**VPN State Machine pattern:** `VpnService` follows an explicit state enum (`IDLE → REQUESTING_PERMISSION → STARTING → CONNECTED → STOPPING → DISCONNECTED`, plus `ERROR`). All async operations use operation-tracking (`startOperation`/`stopOperation` Promises) to serialize start/stop requests. Components subscribe via `vpnService.subscribe()` and clean up in `aboutToDisappear`.

**Native bridge pattern:** The `proxy_core` module wraps N-API functions in thin ArkTS exports. C++ uses the `nlash` namespace, returns typed Core error codes, and logs through `hilog`. Any new native capability should follow the same flow: declare in `napi_init.cpp`, expose in `proxy_core/src/main/ets/index.ets`, and consume via `import { ... } from 'proxy_core'`.

## Testing Guidelines

Tests use `@ohos/hypium` with `describe`, `it`, and `expect`. Name files `*.test.ets`, group behavior by feature, and cover success, failure, and state-transition paths. Add fast logic tests to `src/test` and device/API integration tests to `src/ohosTest`. There is no enforced coverage threshold; every behavior change should include focused regression coverage.

**Current test status:** `entry/src/test/NavigationModels.test.ets` covers navigation, and `UiUtils.test.ets` covers width conversion, responsive breakpoints and local-time formatting. Existing domain, protocol and service tests remain under `entry/src/test/`; scaffold integration tests remain under `entry/src/ohosTest/`. `proxy_core/src/test/` contains the Native module test-suite entry; device-level Native/VPN coverage still needs to be added.

## Adding New Pages

1. Add the primary page enum value to `AppPage` in `model/NavigationModels.ets` and its item to `SIDE_NAV_PAGES` in `constants/NavigationConstants.ets`; also add it to `BOTTOM_NAV_PAGES` if needed.
2. Create the business `@Component` in `entry/src/main/ets/view/`; reusable presentation components belong in `components/`.
3. Add the route and mapping in `navigation/AppNavigationState.ets`, then add its `NavDestination` branch in the `Index` destination builder, preserving the primary-page back behavior.
4. Only independently loaded `@Entry` pages belong in `pages/` and `main_pages.json`. Business `@Component` views hosted by `Index` are not separately registered; the current entry remains `pages/Index`.

## Commit & Pull Request Guidelines

History follows Conventional Commits, for example `feat(vpn): 完善 Core 生命周期`. Use an imperative subject with an optional scope (`feat`, `fix`, `test`, `docs`, `refactor`). Pull requests should explain intent, list validation performed, link related issues, and include screenshots or recordings for UI changes. Call out permission, signing, module, or native ABI changes explicitly.
