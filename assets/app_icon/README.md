# Choir Scheduler App Icon

Source:
- `choir_scheduler_app_icon.svg`

Design:
- Purple gradient background: `#4C1D95` to `#6D3FD1`
- White calendar outline
- Gold music note accent: `#F59E0B`
- No text, optimized for small iPhone home screen sizes

PNG export recommendations:
- Export from the SVG at `1024x1024` for the App Store source icon.
- Generate iOS app icon sizes from the 1024 PNG:
  - 20pt, 29pt, 40pt, 60pt at 2x and 3x
  - 76pt and 83.5pt for iPad if iPad support remains enabled
  - 1024x1024 marketing icon
- Keep the full icon artwork inside the safe area; do not add extra rounded corners to exported PNGs.

Flutter/iOS integration steps:
1. Export `choir_scheduler_app_icon.svg` to a 1024x1024 PNG.
2. Open `ios/Runner/Assets.xcassets/AppIcon.appiconset` in Xcode.
3. Replace the existing AppIcon images with generated PNG sizes.
4. Confirm `ios/Runner/Info.plist` still references `AppIcon`.
5. Run `flutter clean`, then `flutter build ios --release` before TestFlight upload.
