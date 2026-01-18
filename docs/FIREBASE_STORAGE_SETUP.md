# Firebase Storage Setup Guide

## Issue
When running `firebase deploy --only storage`, you get this error:

```
Error: Firebase Storage has not been set up on project 'radiusapp-ecfcd'. 
Go to https://console.firebase.google.com/project/radiusapp-ecfcd/storage 
and click 'Get Started' to set up Firebase Storage.
```

## Solution

Firebase Storage must be enabled in the Firebase Console before you can deploy storage rules.

### Step 1: Enable Firebase Storage

1. Go to [Firebase Console](https://console.firebase.google.com/project/radiusapp-ecfcd/storage)
2. Click **"Get Started"** button
3. A dialog will appear with security rules - click **"Next"**
4. Select your Cloud Storage location (choose one closest to your users):
   - For US users: `us-central1` or `us-east1`
   - For Europe: `europe-west1` or `europe-west2`
   - For Asia: `asia-south1` or `asia-southeast1`
   
   ⚠️ **Important**: Once selected, the location cannot be changed!

5. Click **"Done"**

### Step 2: Verify Storage is Enabled

1. In the Firebase Console, you should now see the Storage page with:
   - A storage bucket (e.g., `radiusapp-ecfcd.appspot.com`)
   - Default rules
   - 0 GB used (Free tier: 5 GB)

### Step 3: Deploy Your Custom Storage Rules

Now you can deploy the custom storage rules from your project:

```bash
cd functions
firebase deploy --only storage
```

Or deploy both Firestore and Storage rules:

```bash
firebase deploy --only firestore:rules,storage
```

## Expected Output

After enabling Storage and deploying, you should see:

```
=== Deploying to 'radiusapp-ecfcd'...

i  deploying storage
i  storage: ensuring required API firebasestorage.googleapis.com is enabled...
✔  storage: required API firebasestorage.googleapis.com is enabled

i  storage: uploading rules storage.rules...
✔  storage: released rules storage.rules to firebase.storage/radiusapp-ecfcd.appspot.com

✔  Deploy complete!
```

## Verify Rules Are Active

1. Go to [Storage Rules in Console](https://console.firebase.google.com/project/radiusapp-ecfcd/storage/rules)
2. You should see your custom rules:
   - Images: 20MB limit
   - Audio: 50MB limit
   - Documents: 100MB limit
   - Stickers: 5MB limit

## Free Tier Limits

Firebase Storage free tier (Spark plan):
- **Storage**: 5 GB
- **Downloads**: 1 GB/day
- **Uploads**: 20,000/day

Monitor usage at: https://console.firebase.google.com/project/radiusapp-ecfcd/usage

## Troubleshooting

### Error: "Firebase CLI not found"
```bash
npm install -g firebase-tools
firebase login
```

### Error: "Insufficient permissions"
Make sure you're logged in with an account that has Owner or Editor role on the Firebase project.

### Error: "storage.rules file not found"
Make sure you're in the `functions` directory or specify the path:
```bash
firebase deploy --only storage --config ../firebase.json
```

## Notes

- The Storage bucket name is auto-generated: `radiusapp-ecfcd.appspot.com`
- All media files will be stored at: `gs://radiusapp-ecfcd.appspot.com/chat_media/`
- Files are organized by type: `images/`, `audio/`, `documents/`, `stickers/`
- Default Storage location cannot be changed after creation
- Consider upgrading to Blaze (pay-as-you-go) plan if you exceed free tier limits

## Next Steps

After enabling Storage:
1. ✅ Deploy storage rules
2. ✅ Test image upload in the app
3. ✅ Monitor storage usage
4. ✅ Set up billing alerts at 80% usage

---

**Last Updated**: January 18, 2026  
**Project**: Radius App  
**Firebase Project ID**: radiusapp-ecfcd
