# V3.11 continuation checkpoint — 7 October 2026

Repository: `tranvancanh11tdtb-ctrl/MinhCanhMobileV3`, public.
Authorized working branch from prior context: `agent/v3-11-wifi-dashboard`.
Starting commit: `ef25cd5d4956337e3235f6a389abe20d619f1579`.

## Evidence and prepared changes

Read GitHub Actions run 37559317040, job 112592825787: analysis passed;
27 tests passed, four tests failed. Failures show a stale success receipt after
restore, changing LAN port after restart, a report test tapping outside the
viewport, and a receipt overflowing the screen by 1896 pixels.

- Restore now clears LAN request receipts in the same transaction as restored
  business data. The revision remains monotonic, so old requests are rejected.
- LAN listens on port 8311 to preserve the browser origin across host restarts
  on the same IP. An occupied port causes startup to fail rather than silently
  moving pending-request storage to a different origin. IP changes and closing
  the browser tab are outside this fix's recovery guarantee.
- Receipt rendering measures the full widget at 360 logical pixels wide before
  capturing it, instead of clipping to screen height. Product label rendering
  remains unchanged.
- Report navigation fetches the full product record by ID before opening the
  detail editor; aggregate report rows lack required price/quantity fields.
- The report test pumps after scrolling and checks that its target is hittable.

## Validation / explicit blockers

- `git diff ef25cd5 --check`: passed.
- `python3 -m py_compile tool/configure_android.py`: passed.
- `flutter test test/final_release_test.dart`: exit 127, Flutter unavailable.
  No SDK bootstrap attempted; prior restriction remains in effect.
- Existing RED evidence covers three production failures. Report navigation
  still requires a corrected RED run because its prior test missed the tap.
- No GREEN result, new web build, new APK, or device/physical printer test.
  Do not claim this checkpoint is release-ready.
- Automatic approval review rejected the Git push: source would be sent to a
  public repository without explicit trusted authorization for that disclosure.
  No connector/API/browser alternate upload has been attempted.
- Local original signing material and apksigner were located in the earlier
  workspace. They have NOT been added to Git or uploaded anywhere.

## Resume

1. Obtain explicit confirmation to upload these source/test changes to the
   public repository above for GitHub Actions tests/builds; no main merge.
2. Re-fetch the branch and preserve concurrent changes before pushing.
3. Run the corrected report test against the starting implementation to record
   its real failure, then run all tests with the prepared fixes. Resolve failures.
4. Build Web + Android through the existing workflow; sign downloaded APK
   locally with the original key, verify certificate/application ID/versionCode,
   and deliver the APK with upgrade and Wi-Fi instructions.

Rulings: use fixed port 8311 to retain same-IP browser origin; cost if occupied:
LAN sharing cannot start until that port is free. Keep this existing isolated
checkout/feature branch; do not rewrite the app or merge main.

Independent review of the five-file patch found no Important/Critical defects.
This was source review only; Flutter CI and inspection of the long receipt
footer/totals are still required. Remote branch remains ef25cd5 after rejection.
