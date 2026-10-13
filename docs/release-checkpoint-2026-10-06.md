# V3.11 release checkpoint — 6 October 2026, evening

## Exact starting state

- Repository: tranvancanh11tdtb-ctrl/MinhCanhMobileV3 (public).
- Authorized feature branch from prior conversation: agent/v3-11-wifi-dashboard.
- Remote starting HEAD: 0bd872b59cd35db32818b1a2c5768cd7761cd75b.
- GitHub Actions run 37417366245 succeeded for that HEAD, including tests, web and APK. This does not verify the new local changes below.
- Downloaded baseline APK is debug-signed, certificate SHA256 f5d0ff58de3306f5bae2bc985c808a86e63cab6f242256aa8f09c47c27363c71. Do not distribute it as an in-place upgrade.
- Original release keystore recovered privately; keytool confirms SHA256 d7154e2a61954557a9bd621f35b208cba9fdbbe53afc48bdf26f6aa1f9364f76, matching prior APK verification. No key/password is in this repository.

## Prepared changes, NOT yet Flutter-tested

- Device-only biometric enablement requires current app PIN and successful system authentication; cancellation retains PIN fallback. Relock after 60 seconds in background, including routes above the home page. Use current stored PIN after a PIN change.
- Distinguish rolled-back LAN writes from lost responses/authentication failures. Release a pending request only after an authoritative noncommit response; retain it after network/auth errors. Add re-pair action.
- Native backups use a transaction snapshot. Both restore paths validate complete version-6 backup structure and preserve a recovery snapshot, with foreign-key verification inside the transaction.
- Notify phone after desktop writes. Block stale native writes until user explicitly confirms refreshing/discarding unsaved drafts.
- Desktop backup downloads a JSON file through a user gesture instead of relying on clipboard availability over HTTP.
- Android AppCompat theme for local_auth.
- Tests added for pending recovery, incomplete restore, debt recovery, stale native writes, biometric policy, mixed invoice restore and competing IMEI sales.

## Verification and blocker

- `git diff --check`: passed.
- `python3 -m py_compile tool/configure_android.py`: passed.
- Executed Android configuration script against generated-file fixture: valid manifest XML, AppCompat theme and packaged web files passed.
- `flutter test`: not run; command exits 127 because Flutter is unavailable locally. Earlier session prohibited repeating local Flutter bootstrap; no bootstrap attempted.
- RED/GREEN evidence for new Flutter tests is missing. Changes remain unverified and must not be called release-ready.
- Automatic approval review rejected `git push origin HEAD:agent/v3-11-wifi-dashboard`: external source/test transfer to GitHub lacked trusted end-user authorization for this destination. No alternate push/API workaround was attempted.

## Next step after explicit authorization

1. Re-read remote HEAD before any push; preserve concurrent changes. Push only the feature branch to the exact repository above, never main. This repository is public; upload only source/tests, never signing material or store backups.
2. Run analysis and full Flutter tests, resolve failures, then build web and APK through the existing upgrade workflow. Verify concurrent IMEI, mixed-data restore and lifecycle behavior.
3. Download APK, sign locally using original private keystore, run apksigner verification, compare certificate, application ID and versionCode with the original app. Preserve existing data.
4. Deliver signed APK with local Wi-Fi pairing/printing instructions. Android hardware, background Wi-Fi and physical printing require device checks; distinguish these from CI results.

## Review rulings

- Keep the existing feature branch and checkout; no restart from the old source ZIP.
- New tests were prepared before fixes, but external test execution was blocked. Do not claim tests passed or hide the missing RED/GREEN cycle.
- Use a conservative phone-wide stale-data guard and explicit reload after desktop writes instead of silently resetting active forms. Cost: user must reload even if the remote change was unrelated to the current form.
- Keep restore format at the current exported version 6; reject older/incomplete objects with an explicit error rather than risking partial data deletion.
