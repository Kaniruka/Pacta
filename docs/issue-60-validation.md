# Issue #60 validation

> 历史适用范围：以下设计、评审及验收记录适用于各节所载日期（2026-10-23 范围调整之前）。原始事实、测试和证据保留；其中无障碍要求及未完成项不再构成未来交付条件，现行范围见 [ADR 0007](adr/0007-accessibility-out-of-product-scope.md)。

Baseline: `ab4ebf0` on `master`. Issue: first National Focus structure analysis from the App.

## Delivered behavior

Both existing My and tree-more entries reach the same guide, retaining four main destinations. The guide explains scope, manual upload, mobile availability, source/freshness, Codex configuration and explicit consent, revocation and recovery. It copies a public GitHub skill-install URL and a first structure-analysis question. Its manual-sync route reuses `CloudSyncCard`: merely opening it does not inspect/upload/download; direction selection and whole-snapshot overwrite consent remain required.

The installable `skills/pacta-national-focus-analysis` skill uses the deployed MCP v1 contract, coherent revision reads, stable card/requirement-version references and facts → possible explanations → suggestions. Synthetic scenarios cover same-name cards, strengthening/version boundaries, pending confirmation, empty collections and insufficient evidence. Real Codex model and remote MCP evidence is recorded in [skill validation](issue-60-skill.md), including the delegated-auth test boundary. No OAuth browser consent retest is claimed for the model run.

## Checks

- Windows Flutter/Dart 3.47.2/3.13.2: changed Dart files formatted; `flutter analyze` passed.
- `flutter test --reporter compact`: all 263 passed.
- `flutter test test/national_focus/national_focus_ai_analysis_page_test.dart`: 7 passed, including 320-wide/2x text/dark and 1200-wide layouts, both entries, copy actions, sync navigation, revoke and error recovery.
- Android 15/API35, `PactaT24Peer` / emulator-5554: `flutter test integration_test/national_focus_ai_device_test.dart -d emulator-5554 --no-uninstall --dart-define=PACTA_CAPTURE_GUIDE=true`: 1 passed. Fake repositories isolate device UI acceptance from real authorization/service checks. Covered both entries, skill/question/config copy, explicit consent/revoke, no implicit sync, upload cancellation and confirmed overwrite. [Captured guide](evidence/issue60-android-guide.png) was visually inspected: readable text, wrapping, labelled controls, scrolling and no clipping in the captured viewport.
- Final Android rerun without the capture pause: 1 passed (27 seconds), including the published-master installation URL copy.
- Windows 11 native `flutter test integration_test/national_focus_ai_device_test.dart -d windows`: 1 passed (24 seconds). Initial native attempts exposed a test-helper error: a rectangle inside the ListView was not necessarily hit-testable at the desktop edge. The helper now centers the control using `Scrollable.ensureVisible` and verifies hit-testability before clicking. This preserves real pointer interactions and all consent/sync assertions.
- Normal Android debug APK rebuilt with only public URL/publishable-key defines and installed with `adb install -r`: passed. Original Android app files restored from a private archive and hashes compared: all 7 original files identical; the one additional test-generated Flutter resource timestamp file was removed. No business data reset or uninstall was performed. Temporary client-define/archive transfer files were removed.
- `git diff --check`: passed. Skill frontmatter validation and JSON parsing passed.

Windows screenshot tooling could not initialize: `codex/sandbox-state-meta: sandboxCwd is not a local file URI`; resetting the JS kernel and retrying failed identically. Windows native integration testing remains independent of that tool. No desktop screenshot, keyboard-only or screen-reader session is claimed.

## Review

Separate Standards and Spec reviews found no blocking issue. Standards review checked repository rules and Fowler smells; shared download-invalidation code is a minor existing-shape duplication, without demonstrated divergence. Spec review confirmed source/upload-time guidance is fulfilled by instructions plus MCP metadata and skill reporting; this ticket does not add the #61 history-reflection workflow. UI review applies HIG accessibility/layout/user-control principles to Flutter Material, retaining existing theme and navigation.

## Publication

Implementation commit `754365b` pushed to `origin/master`. The built-in skill-installer, run with Windows Python 3.14.7 against the public master GitHub URL into an isolated temporary destination, installed successfully. All 4 installed files match repository contents byte-for-byte. The earlier WSL archive transfer stalled and was stopped; the Windows installer completed.
