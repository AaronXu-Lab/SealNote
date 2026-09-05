# Seal Note DMG

The DMG follows Soiawork's 800 × 440 layout and production method: a restrained
aurora background, 180 px app and Applications icons, centered installation copy,
and a three-chevron drag direction indicator. Seal Note's compiled app icon is
also used as the volume icon, so the application bundle is never modified after
signing.

Build a Release DMG with the current Xcode signing configuration:

```bash
./script/package_dmg.sh
```

Package an already exported and notarized Developer ID application without
changing its signature:

```bash
APP_PATH="/path/to/Seal Note.app" ./script/package_dmg.sh
```

The output defaults to `dist/Seal-Note-<version>.dmg`. `APP_PATH`, `VERSION`, and
`OUTPUT_DMG` may be overridden. A Developer ID identity and notarization
credentials are intentionally not embedded in this repository.
