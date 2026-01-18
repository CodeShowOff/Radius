# Media Upload Feature Flag

## Current Status: 🚧 DISABLED

Media uploads (images, voice messages, documents, stickers) are currently **disabled** to avoid Firebase Storage costs.

All logic is in place, but users will see friendly "coming soon" messages instead of upload errors.

---

## What Users See

When trying to send media:

- 📷 **Photo**: "Photo sharing will be available very soon! We're setting up our servers."
- 🎤 **Voice Message**: "Voice messages will be available very soon! We're setting up our servers."
- 📄 **Document**: "Document sharing will be available very soon! We're setting up our servers."
- 😊 **Sticker**: "Stickers will be available very soon! We're setting up our servers."

These messages appear as dismissible SnackBars at the bottom of the screen.

---

## How to Enable When Ready

### Step 1: Set Up Firebase Storage (One-time)

1. Go to [Firebase Console Storage](https://console.firebase.google.com/project/radiusapp-ecfcd/storage)
2. Click **"Get Started"**
3. Choose location (e.g., `us-central1`) - **cannot be changed later!**
4. Click "Done"

### Step 2: Deploy Storage Rules

```bash
cd functions
firebase deploy --only storage
```

Or deploy both Firestore and Storage:
```bash
firebase deploy --only firestore:rules,storage
```

### Step 3: Enable Feature Flag

Open `lib/core/constants/app_constants.dart` and change:

```dart
// Change from:
static const bool enableMediaUploads = false;

// To:
static const bool enableMediaUploads = true;
```

### Step 4: Rebuild the App

```bash
flutter clean
flutter pub get
flutter run
```

That's it! Media uploads will now work.

---

## Benefits of This Approach

✅ **No Code Changes**: All upload logic remains intact  
✅ **User-Friendly**: Clear messages instead of errors  
✅ **Easy Toggle**: Single constant to enable/disable  
✅ **No Crashes**: App works perfectly without Storage  
✅ **No Costs**: Firebase Storage not accessed until enabled  

---

## What Still Works

Even with media disabled:
- ✅ Text messages
- ✅ Message delivery & read receipts
- ✅ Typing indicators
- ✅ Message timestamps
- ✅ Conversation list
- ✅ All other app features

---

## Cost Considerations

### Firebase Storage Free Tier (Spark Plan)
- **Storage**: 5 GB
- **Downloads**: 1 GB/day
- **Uploads**: 20,000/day

### When to Upgrade to Blaze Plan
Only if you exceed free tier limits. Monitor at:
https://console.firebase.google.com/project/radiusapp-ecfcd/usage

### Estimated Costs (if you upgrade)
Based on typical usage:
- 100 users × 10 images/day × 500KB = ~50MB/day storage growth
- Would take **100 days** to reach 5GB free limit
- After that: ~$0.026/GB/month = **$0.13/month** for 5GB

💡 **Recommendation**: Start with free tier, monitor usage, only pay if needed.

---

## Testing the Feature Flag

### Test Disabled State (Current):
1. Open chat
2. Try to send photo → See "coming soon" message
3. Try to send voice → See "coming soon" message
4. Text messages work normally ✅

### Test Enabled State (After setup):
1. Change `enableMediaUploads = true`
2. Rebuild app
3. Send photo → Should upload to Firebase Storage
4. Send voice → Should upload successfully

---

## Files Modified

- `lib/core/constants/app_constants.dart` - Added `enableMediaUploads` flag
- `lib/features/chat/presentation/bloc/chat_bloc.dart` - Added checks for each media type

All other media upload code (MediaUploadService, UI widgets, etc.) remains unchanged and ready to use.

---

**Last Updated**: January 18, 2026  
**Feature Status**: Disabled (no Firebase Storage costs)  
**Enable When**: Firebase Storage is set up and you're ready for media uploads
