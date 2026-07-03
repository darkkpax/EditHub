# EditHub — agent guide

Video-editor project manager for Windows (project folders, footage downloads,
auto-sort, offload to iCloud, DaVinci/Premiere launch).

## Which app is live
- **`flutter_app/`** — the active app (native Flutter Windows). All new work goes here.
- `windows/` — legacy Electron app, kept for reference only. Don't add features to it.

## Build / verify (flutter_app)
```
cd flutter_app
flutter analyze          # must be clean
flutter build windows --release   # must exit 0
```
Output: `flutter_app/build/windows/x64/runner/Release/edithub.exe`.
Installer script: `flutter_app/installer/edithub.iss` (Inno Setup).

## Release policy — SHIP UPDATES WITHOUT BEING ASKED
The user runs an installed build that auto-updates via WinSparkle from GitHub
Releases. So the user does not want to remind anyone to cut releases.

**After any user-facing change to `flutter_app/`, once `flutter analyze` is clean
and `flutter build windows --release` exits 0:**
1. Bump `version:` in `flutter_app/pubspec.yaml` (patch by default, e.g.
   `1.0.0+1` → `1.0.1+2`).
2. Commit the changes to `master`.
3. Tag and push: `git tag vX.Y.Z && git push origin master --tags`
   (tag version must equal the new pubspec version).
4. The **`.github/workflows/flutter-release.yml`** Action then builds the
   installer + `appcast.xml` and publishes the GitHub Release automatically.
   The user's installed app self-updates on next launch.

This is standing authorization: bump + tag + push on your own after verified,
user-facing changes. Skip a release only for pure docs/comment/test-only edits.

## How auto-update works
- App checks `https://github.com/darkkpax/EditHub/releases/latest/download/appcast.xml`
  on launch + every 6h (`lib/services/updater_service.dart`, release builds only).
- Appcast enclosure points to `EditHub-Setup-<version>.exe`; WinSparkle runs it
  silently (`/VERYSILENT /NORESTART`).
- Appcast is currently **unsigned over HTTPS**. If WinSparkle rejects unsigned
  updates, add an EdDSA `sparkle:edSignature` (see the comment in the workflow).

## Compatibility invariants (do not break)
- Settings file: `~/.edithub/settings.json` (same keys as the Electron app).
- Project manifest: `.edithub.json`; archive root: `{icloudPath}/edithub/Videos/{year}/{month}`.
- Project id: `sha1(path.toLowerCase())[:32]`.
