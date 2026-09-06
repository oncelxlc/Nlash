# Repository Guidelines

## Project Structure & Module Organization

Nlash is a HarmonyOS VPN application with ArkTS UI, a C++17 N-API bridge, and a Go/Mihomo core.

- `entry/src/main/ets/`: `pages/` holds entry pages, `view/` business components, and `components/` reusable UI. Keep domain types in `model/`, values in `constants/`, and helpers in `utils/`; preserve existing `stores/`, `services/`, `repository/`, and `navigation/` responsibilities.
- `proxy_core/src/main/`: ArkTS exports in `ets/`, native bridge and CMake configuration in `cpp/`.
- `native-core/`: Go core, tests, pinned versions, and OHOS build scripts.
- `entry/src/main/resources/` and `AppScope/resources/`: strings, themes, icons, and application assets.
- `docs/`: build instructions and regression reports.

## Build, Test, and Development Commands

Use DevEco Studio's bundled OHPM and Hvigor; no wrapper is committed. Set `DEVECO_SDK_HOME` to your SDK directory and add the tools to `PATH`. See `docs/build-and-test.md` for PowerShell paths. Run from the repository root:

- `ohpm install`: install ArkTS dependencies.
- `./native-core/build-ohos.ps1`: test and build the pinned native core, then synchronize ARM64 prebuilts into `proxy_core`.
- `hvigorw.bat assembleHap --no-daemon`: build the application HAP.
- `hvigorw.bat test --no-daemon`: run configured Hypium unit tests.

Use DevEco Studio's Run action with local signing to launch on a device. For Go-only checks, run inside `native-core/`:

```powershell
$env:CGO_ENABLED = '0'
go test .
```

## Coding Style & Naming Conventions

ArkTS uses two-space indentation, semicolons, single quotes, explicit API types, PascalCase types/components, camelCase functions/variables, and UPPER_SNAKE_CASE constants. Models must not import services, utilities, or constants. Follow `code-linter.json5` through DevEco's linter. C++ uses four-space indentation and the `nlash` namespace; format Go with `gofmt`. Reuse existing patterns before introducing dependencies or abstractions.

## Testing Guidelines

Use `@ohos/hypium` in `entry/src/test/` and `proxy_core/src/test/`; name suites `*.test.ets` and register them in the corresponding `List.test.ets`. Go uses standard `testing` with `*_test.go`. No coverage threshold is configured; add focused regression tests for changed behavior. Device suites live in `entry/src/ohosTest/`.

Prefer emulator validation for simple UI styling, layout, copy, basic navigation, and other hardware-independent changes. Use a real device only when explicitly requested or when hardware/system behavior makes emulator results insufficient, including VPN authorization, TUN, socket protection, network switching, sensor-driven handedness, and physical fold transitions.

## Commit & Pull Request Guidelines

Follow history's Conventional Commits, e.g. `fix(ui): 修复返回桌面功能异常`. Keep commits focused. PRs should explain intent, link relevant issues, record validation, and include screenshots for UI changes. Highlight permission, signing, and native ABI changes.

## Security & Configuration

Never commit credentials, signing materials, `.env`, `local.properties`, or generated build/cache directories. Preserve native version pins and third-party notices; follow the distribution restrictions documented in `native-core/README.md`.
