<div align="center">

# Pacta

**Turn every day into a reviewable chain of promises: tasks, focus, national focus and schedules on one timeline.**

[![Flutter checks](https://github.com/Kaniruka/Pacta/actions/workflows/flutter-checks.yml/badge.svg?branch=master)](https://github.com/Kaniruka/Pacta/actions/workflows/flutter-checks.yml)
[![Release](https://github.com/Kaniruka/Pacta/actions/workflows/release.yml/badge.svg)](https://github.com/Kaniruka/Pacta/actions/workflows/release.yml)
[![version](https://img.shields.io/badge/version-0.3.0%2B3-blue)](pubspec.yaml)
[![license](https://img.shields.io/badge/license-GPL--3.0-blue)](LICENSE)

[简体中文](README.md) · [English](README.en.md)

</div>

A self-regulation app built with Flutter for Android and Windows. All state lives locally in Drift/SQLite; once signed in, Supabase Auth, PostgreSQL and RLS sync it across devices with per-user isolation.

## Modules

| Module | Source | Purpose |
| --- | --- | --- |
| Board | `lib/src/board` | Today's promises, national-focus hints, focus entry |
| Focus chain | `lib/src/focus` | Timers, chain history, clock-jump review |
| National focus | `lib/src/national_focus` | National focus cards, checkpoints, reminders |
| Plan | `lib/src/plan`, `lib/src/schedules` | Goals, tasks, schedules, reminder plans |
| My | `lib/src/profile`, `lib/src/sync` | Account, sync state, cloud snapshot history |

## Quick start

Requires Flutter 3.47.2 / Dart 3.13.2, Python 3 and JDK 17; Windows builds need the Visual Studio C++ desktop workload, Android builds need the Android SDK. Start with `flutter doctor -v`.

```powershell
git clone https://github.com/Kaniruka/Pacta.git
cd Pacta
Copy-Item .env.example .env          # fill SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY
python scripts/fetch_misans.py       # first run: fetch and verify MiSans from Xiaomi
python scripts/pacta_build.py run -d windows
```

`scripts/pacta_build.py` is the only supported entry point for running and building: it copies just `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` into a temporary JSON file (deleted afterwards) for `--dart-define-from-file`, so the raw `.env` never reaches a Flutter command line.

| Command | Purpose |
| --- | --- |
| `python scripts/pacta_build.py` | Interactive menu (or pass `interactive` / `-i`) to run, build or initialize signing |
| `python scripts/pacta_build.py run -d windows` | Desktop debugging; `-d android` picks the first Android device, or pass `-d <device-id>` |
| `python scripts/pacta_build.py run -d emulator-5554 --profile` | Explicit device and build mode (`--debug`/`--profile`/`--release`) |
| `python scripts/pacta_build.py build --target apk --release --split-per-abi` | Per-ABI APKs |
| `python scripts/pacta_build.py build --target appbundle --release` | Google Play AAB |
| `python scripts/pacta_build.py build --target windows --release` | Windows release |
| `python scripts/pacta_build.py build --target all --release --require-release-signing` | Everything, failing on a missing release signature |
| `python scripts/pacta_build.py build --target apk --dry-run` | Print the redacted plan only, run nothing |
| `python scripts/pacta_build.py init-keystore` | Generate the local Android release signature |

Keys outside the whitelist (`SUPABASE_SECRET_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_ACCESS_TOKEN`, `TEST_*`, `ANDROID_KEYSTORE_*`) are never injected, never written to the temporary file and never logged. A build with either client key missing stops with a clear message and exit code `2`.

## Android release signing

```powershell
python scripts/pacta_build.py init-keystore
```

Creates two git-ignored files: `android/app/upload-keystore.jks` and `android/key.properties` (`storeFile=upload-keystore.jks`, a random 24-character alphanumeric password, `keyAlias=pacta-upload`). The script reports paths and secret names only, never the passwords, and refuses to overwrite without `--force`.

`android/app/build.gradle.kts` reads `android/key.properties` first, then the environment variables `ANDROID_KEYSTORE_PATH` / `ANDROID_KEYSTORE_PASSWORD` / `ANDROID_KEY_ALIAS` / `ANDROID_KEY_PASSWORD`. Only a complete set creates `signingConfigs.release`; locally, a missing signature falls back to the debug key with a loud warning, while `--require-release-signing` (or `-PrequireReleaseSigning=true`) fails during Gradle configuration.

### GitHub Secrets

| Secret | Value |
| --- | --- |
| `SUPABASE_URL` | Supabase project URL |
| `SUPABASE_PUBLISHABLE_KEY` | publishable key |
| `ANDROID_KEYSTORE_BASE64` | output of the command below |
| `ANDROID_KEYSTORE_PASSWORD` | `storePassword` from `key.properties` |
| `ANDROID_KEY_ALIAS` | `keyAlias` from `key.properties` (default `pacta-upload`) |
| `ANDROID_KEY_PASSWORD` | `keyPassword` from `key.properties` |

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("android/app/upload-keystore.jks"))
```

On tag builds `release.yml` fails explicitly when a signing secret is missing; a manual `workflow_dispatch` without secrets skips the Android job with an explanation and still builds Windows artifacts.

## Deploy your own Supabase

1. Create a Supabase project, enable Email auth and turn **Confirm email** off; sign-up eligibility is enforced by a database allowlist, and the app sends no verification mail and offers no self-service reset.
2. Copy the Project URL and publishable key from Connect into your local `.env`.
3. Push the migrations:

   ```powershell
   pnpm install --frozen-lockfile
   pnpm exec supabase login
   pnpm exec supabase link --project-ref <project-ref>
   pnpm exec supabase db push
   ```

4. Run `python scripts/pacta_admin.py` to create the first account and grant sign-up eligibility. It uses `SUPABASE_SECRET_KEY` (project-owner CLI) and never ships in the client.
5. Accept registration, sign-in and data isolation with a normal user; the permission and RLS probes live in `supabase/tests/`.

See the [Supabase notes](supabase/README.md) and the [Supabase CLI workflow](https://supabase.com/docs/guides/local-development/cli-workflows).

## Versioning and tags

- The single source of truth is `version: MAJOR.MINOR.PATCH+BUILD` in `pubspec.yaml`, mirrored by the `#else` fallback macros in `windows/runner/Runner.rc`.
- `MAJOR` for incompatible changes, `MINOR` for new or restructured primary destinations and data-structure upgrades, `PATCH` for fixes and polish; `+BUILD` only ever increases and never resets.
- Annotated tags follow `vMAJOR.MINOR.PATCH` and are created only on `master` release points. `release.yml` verifies the tag against `pubspec.yaml` (ignoring `+BUILD`) and fails on a mismatch.
- `0.x` is a test stage: interfaces and data formats can still change, so every `v0.*` GitHub Release is marked as a prerelease.

## Before committing

```powershell
flutter analyze
flutter test
python scripts/check_repository_hygiene.py
python -m unittest discover -s scripts -p "test_*.py"
```

## License

[GPL-3.0](LICENSE). MiSans ships under Xiaomi's official licence; see [assets/fonts/README.md](assets/fonts/README.md).
