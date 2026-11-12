# #75 review fixes and Android board capture diagnosis

2026-11-13. Fresh implementer, isolated `ui/75-review-fixes` worktree. No production changes.

## Review suggestion

Standards report: zero hard violations, one P3 duplicated frozen cloud metadata fixture. Spec report: zero code findings. `FrozenUi79Remote` in `test/support` now supplies the identical timestamp to both the #79 widget test and #69 device presentation fixture. No general screenshot framework was introduced.

## Capture feedback loop

Existing public seam: offline AppShell/repositories, existing board pilot fixture, existing screenshot driver and `scripts/run_focus_pilot.py`. Only emulator-5554 (1080×1920, density420, dpr2.625) used; physical device and Windows were untouched. No uninstall, clear-data or database deletion was requested.

Command shape: `python scripts/run_focus_pilot.py --target board --scenario long --view narrow --device emulator-5554 --run-id <id>`. Each evidence folder below has its original run.log and manifest/source hashes; natural failures also have runner run.rc/process_rc. Probe1 was terminated by coordinator, with `interrupted.txt` instead of a fabricated exit code.

Evidence root: `C:/Users/Stray/.codex/worktrees/spec75-review-fixes/Pacta/build/ui-layout-evidence/board-pilot/runs/`.

| Run id | Single change / result |
| --- | --- |
| review75-probe1 | Original implementation reproduces expanded screenshot hang after driver connected. Coordinator terminated only runner PID41668 tree and force-stopped isolated app; no Flutter exit code. |
| review75-probe2 | Add Android convert/capture stage logs and 20-second Future.timeout. Convert succeeds; capture times out, natural rc1. |
| review75-probe3 | Replace conversion's single pump with pumpAndSettle. Same capture timeout, natural rc1. |
| review75-probe4 | Temporarily fullyLive only during capture. Same capture timeout, natural rc1. |
| review75-probe5 | Remove Android physicalSize override. All three captures and touch flows complete, natural rc0. |
| review75-probe6 | Remove temporary fullyLive again: natural rc0; opened expanded image is complete. |

The negative/positive differential isolates Android physicalSize override as the cause. Test render dimensions 411×731 times2.625 are fractional physical dimensions, while native ImageView captures the actual1080×1920 surface. Native screen and test viewport must agree. The actual resulting viewport is411.43×731.43 logical pixels (411-width class), normal text scale1.0. This is not an exact411×731 claim. Driver handshaking and conversion had already completed in failed runs.

SDK evidence: integration_test Android `FlutterDeviceScreenshot.captureView` waits for `acquireLatestImageViewFrame`; live-test Dart scheduling is a separate concern. PumpAndSettle and fullyLive experiments alone did not fix the symptom. Permanent bounded waits are only on the Android evidence capture, not production UI.

## Validation

`dart format` modified Dart files; `flutter analyze`: no issues. `python -m unittest discover -s scripts -p test_run_focus_pilot.py`:12 pass. `flutter test test/sync/issue_79_sync_presentation_test.dart test/board/board_integration_test.dart test/board/goal_task_description_test.dart`:12 pass. `flutter test --no-pub test/sync/cloud_sync_card_test.dart test/sync/manual_cloud_sync_app_test.dart`:10 pass.

Probe5 expanded screenshot was opened: complete estimate/focused/pending/deadline facts wrap at normal text size; long title/description and bottom navigation remain readable. Final evidence and scope are recorded below after clean reruns.

## First-frame check

The additional `review75-final-long` single-pump minimisation returned rc0, but opening expanded.png revealed an all-dark first frame. Collapsed/restored images were complete. This run is not final visual acceptance. A pumpAndSettle-only rerun (`review75-accepted-long`) also returned rc0 with a dark expanded image. Settling alone is insufficient; conversion of an idle scene requires an explicit repaint. No fullyLive policy change is retained. The companion `review75-final-support` run used the same single-pump code and is likewise not used as final acceptance. Original artifacts remain untouched.

## Final scene repaint

`review75-repaint-long-long-narrow`: natural runner rc0, process_rc0, no source drift. After conversion the existing RepaintBoundary is marked dirty, then pumped/settled; this generates a fresh scene on the native image surface. Opened expanded image is now complete. Android instrumented touch path completed fold, goal editor cancel, deletion cancel, task edit cancel, save, restore, focus setup cancel. Actual logical viewport411.43×731.43, normal text1.0, dark.

Final long images (absolute):
- `C:/Users/Stray/.codex/worktrees/spec75-review-fixes/Pacta/build/ui-layout-evidence/board-pilot/runs/review75-repaint-long-long-narrow/board-long-narrow-expanded.png`
- `C:/Users/Stray/.codex/worktrees/spec75-review-fixes/Pacta/build/ui-layout-evidence/board-pilot/runs/review75-repaint-long-long-narrow/board-long-narrow-collapsed.png`
- `C:/Users/Stray/.codex/worktrees/spec75-review-fixes/Pacta/build/ui-layout-evidence/board-pilot/runs/review75-repaint-long-long-narrow/board-long-narrow-restored.png`

Native cross-check limitation: `native-during-flow.png` in this run, acquired through adb and opened, contains Android's “Pacta isn't responding” overlay over the correctly rendered board. Startup logs show skipped261frames and signal3; driver had been paused/resumed at startup and then progressed normally. Cause of the ANR was not established. Coordinator clicked only this isolated app's visible Wait button. Driver screenshots capture FlutterView and omit native system dialogs, so they must not be claimed to prove absence of system overlays or unattended native responsiveness. No production performance change was made to hide this limitation.

`review75-repaint-support-default-narrow`: same final source hashes as repaint-long, natural runner rc0/process_rc0, no drift. Expanded and support images both opened and complete. Support image preserves national-focus confirmation1, seven daily bars13min each, total91min, read-only empty calendar and bottom navigation. Instrumented touch opens the national-focus tree and returns to board.

Final support images (absolute):
- `C:/Users/Stray/.codex/worktrees/spec75-review-fixes/Pacta/build/ui-layout-evidence/board-pilot/runs/review75-repaint-support-default-narrow/board-default-narrow-expanded.png`
- `C:/Users/Stray/.codex/worktrees/spec75-review-fixes/Pacta/build/ui-layout-evidence/board-pilot/runs/review75-repaint-support-default-narrow/board-default-narrow-support.png`

Final commands: existing runner with `--target board --scenario long --view narrow --device emulator-5554 --run-id review75-repaint-long`, then scenario`default`, run-id`review75-repaint-support`. Final code formatted and analyzed without issues. Twenty-two relevant widget tests and twelve runner tests passed as listed above. Device released immediately after final support images were opened; no running acceptance job left. No claim of Windows verification or real-cloud verification is made by this helper/capture-only work.

## Android interactive hold follow-up

The later native-board-touch run against40649e9 returned runner rc0 without source drift, but showed Android ANR before any task interaction. Clicking Wait once did not establish recovery, and no real task touch path was completed. It does **not** pass native interactive acceptance. Read-only lastanr evidence reports `FocusEvent(hasFocus=true)`5004ms timeout; this does not establish the ImageView as the ANR cause.

The accepted focus-chain pilot already retains Android's native surface during manual input and pumps every100ms. Board now reuses that local pattern: when Android hold>0, skip initial expanded screenshot/conversion, enable native pointer propagation, emit `BOARD_PILOT_INSPECTION_READY`, then alternate100ms tester.pump and100ms runAsync delay until the hold deadline. Restore the prior pointer setting in finally, settle, and only then capture `after-hold`. This is an interactive evidence path; it does not assert that the ANR cause is proven or resolved. Windows resize/capture loop and automatic Android long/default paths are unchanged.

For `--target board --scenario long --view narrow --manual-hold 180`, the post-hold driver image is `board-long-narrow-after-hold.png` inside that run's unique evidence directory. Before READY, expected log is `[board-pilot] manual-expanded hold=180s nativeSurface=true`; there must be no `[board-capture] convert begin` before READY/hold completion. After hold, expect `[board-pilot] after-hold ...`, conversion/capture stage logs, and natural runner rc. The independent native-board-touch worker must verify actual Android interactions and native screenshots; no device was started for this follow-up implementation.

Follow-up validation: `dart format integration_test/board_design_device_test.dart`; `flutter analyze --no-pub` no issues; `python -m unittest discover -s scripts -p test_run_focus_pilot.py`12 pass. `git diff --check` clean. Native manual acceptance remains pending the independent worker rerun.
