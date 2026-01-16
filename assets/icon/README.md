# App Icon Setup

## Instructions

1. **Add your Radius app icon** to this directory as `app_icon.png`
   - Recommended size: **1024x1024 pixels**
   - Format: PNG with transparency (if needed)
   - This will be your main app icon shown when the app opens

2. **Run the following commands** to generate icons for all platforms:
   ```bash
   flutter pub get
   dart run flutter_launcher_icons
   ```

3. The icon generator will automatically create all necessary icon sizes for:
   - Android (all densities)
   - iOS (all sizes)
   - Web
   - macOS
   - Windows

## Tips
- Make sure your icon looks good at small sizes (48x48, 72x72)
- For Android adaptive icons, ensure important content is centered
- Test the icon on both light and dark backgrounds
