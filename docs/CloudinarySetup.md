# Cloudinary Setup Guide

## Overview
Cloudinary is now integrated into the app for profile image uploads. Follow these steps to configure your Cloudinary account.

## Setup Steps

### 1. Create Cloudinary Account
1. Go to [https://cloudinary.com](https://cloudinary.com)
2. Sign up for a free account
3. Verify your email

### 2. Get Your Credentials
After logging in, you'll see your dashboard with these credentials:

- **Cloud Name**: Your unique cloud identifier
- **API Key**: Your public API key
- **API Secret**: Your private API secret (keep this secure!)

### 3. Create Upload Preset
1. In Cloudinary dashboard, go to **Settings** (gear icon)
2. Click on **Upload** tab
3. Scroll down to **Upload presets** section
4. Click **Add upload preset**
5. Configure the preset:
   - **Signing Mode**: Select "Unsigned"
   - **Preset name**: Enter a name (e.g., "radius_profile_uploads")
   - **Folder**: Enter "radius/profiles" (optional but recommended)
   - Click **Save**

### 4. Update the App Configuration
Open `lib/core/services/cloudinary_service.dart` and update:

```dart
class CloudinaryService {
  // Update these with your Cloudinary credentials
  static const String cloudName = 'YOUR_CLOUD_NAME';        // From dashboard
  static const String uploadPreset = 'YOUR_UPLOAD_PRESET';   // Preset name you created
  
  // Optional: For signed uploads (more secure)
  static const String apiKey = 'YOUR_API_KEY';               // From dashboard
  static const String apiSecret = 'YOUR_API_SECRET';         // From dashboard
}
```

### 5. Test the Integration
1. Run the app: `flutter run`
2. Navigate to Edit Profile
3. Tap the camera icon on the profile picture
4. Choose "Take Photo" or "Choose from Gallery"
5. Select an image
6. The image should upload and display

## Image Upload Features

### Current Implementation
- **Max Size**: Images are compressed to 1024x1024 pixels
- **Quality**: 85% JPEG quality
- **Sources**: Camera or Gallery
- **Storage**: Cloudinary CDN with automatic optimization
- **Transformations**: Auto format, auto quality, max 800x800 display

### Upload Flow
1. User taps camera icon on avatar
2. Bottom sheet shows options: Camera, Gallery, Remove Photo
3. User selects image source
4. Image picker opens
5. Image is compressed locally
6. Uploaded to Cloudinary
7. URL saved to Firestore user profile
8. Profile updates with new photo URL

### Security
- Uses **unsigned uploads** for simplicity
- Upload preset controls allowed file types and sizes
- Cloudinary handles image validation
- For production, consider switching to **signed uploads** for added security

## Advanced Configuration (Optional)

### Signed Uploads
For better security in production:

```dart
// In cloudinary_service.dart, use uploadImageSigned() instead of uploadImage()
final url = await _cloudinaryService.uploadImageSigned(
  imageFile: file,
  folder: 'radius/profiles',
);
```

### Upload Preset Settings
Recommended preset configuration:
- **Allowed formats**: jpg, png, webp
- **Max file size**: 10 MB
- **Max dimensions**: 2048x2048
- **Auto-tagging**: Enable for better organization
- **Backup**: Enable for data safety

### Folder Structure
Suggested folder organization:
- `radius/profiles` - User profile pictures
- `radius/groups` - Group photos (future feature)
- `radius/chat` - Chat media (future feature)

## Troubleshooting

### Upload Fails
- Check internet connection
- Verify Cloudinary credentials are correct
- Check upload preset is set to "Unsigned"
- Ensure preset name matches exactly

### Image Not Displaying
- Check Firestore has correct photoUrl field
- Verify URL format: `https://res.cloudinary.com/YOUR_CLOUD_NAME/...`
- Check image was uploaded to correct folder

### Permissions Issues
On Android/iOS, ensure permissions are granted:
- **Camera**: Needed for taking photos
- **Gallery/Photos**: Needed for selecting images

## Cost Considerations

### Free Tier Limits (Cloudinary)
- **Storage**: 25 GB
- **Bandwidth**: 25 GB/month
- **Transformations**: 25 credits/month
- **Images**: Unlimited

This should be sufficient for:
- ~25,000 profile images (assuming 1MB average)
- Small to medium user base
- Development and testing

### Scaling
If you exceed free tier:
- Upgrade to paid plan
- Implement client-side compression
- Add image caching
- Consider alternative storage (Firebase Storage)

## Next Steps

1. ✅ Complete this setup guide
2. ✅ Test image upload flow
3. 🔲 Configure upload preset limits
4. 🔲 Add error handling for failed uploads
5. 🔲 Implement image deletion when user removes photo
6. 🔲 Add loading states during upload
7. 🔲 Consider switching to signed uploads for production

## Support
- Cloudinary Docs: [https://cloudinary.com/documentation](https://cloudinary.com/documentation)
- Flutter Image Picker: [https://pub.dev/packages/image_picker](https://pub.dev/packages/image_picker)
