# Chat Media Features - Complete Guide

## Overview
Your chat feature now supports all WhatsApp-like media features:
- ✅ **Text messages** (already working)
- ✅ **Images** (camera & gallery)
- ✅ **Voice messages** (audio recording)
- ✅ **Documents** (PDF, DOC, DOCX, XLS, XLSX, TXT)
- ✅ **Stickers** (images sent as stickers)

## Storage Architecture

### Firestore (Free tier: 1GB storage, 20K writes/day)
Stores message metadata:
- Message text
- Message type (text, image, audio, document, sticker)
- Media URLs (links to files in Storage)
- File metadata (name, size, duration)
- Timestamps, read receipts, etc.

### Firebase Storage (Free tier: 5GB storage, 50K downloads/day)
Stores actual media files:
```
chat_media/
  ├── images/       (20MB per file limit)
  ├── audio/        (50MB per file limit)
  ├── documents/    (100MB per file limit)
  └── stickers/     (5MB per file limit)
```

## How to Deploy Security Rules

### 1. Deploy Firestore Rules
```bash
firebase deploy --only firestore:rules
```

### 2. Deploy Storage Rules
```bash
firebase deploy --only storage
```

### 3. Deploy Both
```bash
firebase deploy --only firestore:rules,storage
```

## Features Implemented

### 1. **Send Images**
- **From Gallery**: Tap attachment button → Gallery → Select image
- **From Camera**: Tap attachment button → Camera → Take photo
- **Features**:
  - Automatic compression (max 1920x1920, 85% quality)
  - Progress tracking during upload
  - Click to view full size
  - Optional caption support

### 2. **Send Voice Messages**
- **Recording**: Tap and hold mic button
- **Features**:
  - Real-time recording indicator
  - Duration counter
  - Auto-stop at 5 minutes
  - Cancel by swiping left or tapping delete
  - Playback with progress bar
  - Duration display

### 3. **Send Documents**
- **Select**: Tap attachment button → Document
- **Supported formats**: PDF, DOC, DOCX, XLS, XLSX, TXT
- **Features**:
  - File name display
  - File size display
  - Tap to download/open
  - 100MB size limit

### 4. **Send Stickers** (Future Enhancement)
- Currently supported but requires sticker pack implementation
- Same flow as images but displayed differently

## Required Permissions

### Android (`android/app/src/main/AndroidManifest.xml`)
```xml
<!-- Camera -->
<uses-permission android:name="android.permission.CAMERA"/>

<!-- Microphone for voice messages -->
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS"/>

<!-- Storage (for older Android versions) -->
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>
```

### iOS (`ios/Runner/Info.plist`)
```xml
<!-- Camera -->
<key>NSCameraUsageDescription</key>
<string>Camera access is needed to take photos for messages</string>

<!-- Photo Library -->
<key>NSPhotoLibraryUsageDescription</key>
<string>Photo library access is needed to send images</string>

<!-- Microphone -->
<key>NSMicrophoneUsageDescription</key>
<string>Microphone access is needed to record voice messages</string>
```

## Code Structure

### Core Services
1. **MediaUploadService** (`lib/features/chat/data/media_upload_service.dart`)
   - Handles all file uploads to Firebase Storage
   - Progress tracking
   - Error handling
   - File type validation

2. **ChatService** (`lib/features/chat/data/chat_service.dart`)
   - Extended with `sendMediaMessage()` method
   - Stores media metadata in Firestore
   - Updates conversation with media type indicators

### UI Components
1. **ChatInput** (`lib/features/chat/presentation/widgets/chat_input.dart`)
   - Attachment button with bottom sheet
   - Voice recording button (when no text)
   - Send button (when text entered)

2. **MediaMessageContent** (`lib/features/chat/presentation/widgets/media_message_content.dart`)
   - Displays different media types
   - Image preview with CachedNetworkImage
   - Audio player with progress bar
   - Document viewer with download option

3. **VoiceRecorderWidget** (`lib/features/chat/presentation/widgets/voice_recorder_widget.dart`)
   - Real-time recording UI
   - Duration counter
   - Cancel and send actions

### BLoC Events
New events in `ChatBloc`:
- `ChatSendImage` - Upload and send image
- `ChatSendAudio` - Upload and send voice message
- `ChatSendDocument` - Upload and send document
- `ChatSendSticker` - Upload and send sticker

## Testing the Features

### 1. Test Image Upload
```dart
// From gallery
context.read<ChatBloc>().add(ChatSendImage(imageFile, source: ImageSource.gallery));

// From camera
context.read<ChatBloc>().add(ChatSendImage(imageFile, source: ImageSource.camera));
```

### 2. Test Voice Message
```dart
context.read<ChatBloc>().add(ChatSendAudio(audioFile, duration: 45));
```

### 3. Test Document Upload
```dart
context.read<ChatBloc>().add(ChatSendDocument(documentFile, caption: 'Contract'));
```

## Troubleshooting

### Issue: "Permission denied" error
**Solution**: Make sure you've deployed both Firestore and Storage security rules.

### Issue: "Upload failed" error
**Solution**: 
1. Check file size limits
2. Verify user is authenticated
3. Check Firebase Storage quota

### Issue: Audio not playing
**Solution**:
1. Ensure `audioplayers` package is installed
2. Check audio file format (m4a, mp3, etc.)
3. Verify media URL is accessible

### Issue: Images not loading
**Solution**:
1. Check Firebase Storage CORS configuration
2. Verify download URLs are public
3. Check internet connection

## Cost Estimates (Free Tier Limits)

### Firestore
- **Storage**: 1 GB (messages metadata)
- **Reads**: 50K/day
- **Writes**: 20K/day
- **Deletes**: 20K/day

### Firebase Storage
- **Storage**: 5 GB (actual media files)
- **Downloads**: 1 GB/day
- **Uploads**: 1 GB/day

### Typical Usage
- 1000 users sending 10 images/day = ~500MB/month
- Voice messages: ~50KB each
- Documents: varies greatly

**Note**: You'll likely stay within free tier unless you have 1000+ daily active users.

## Future Enhancements

1. **Video Messages**
   - Add video player
   - Thumbnail generation
   - Compression before upload

2. **Sticker Packs**
   - Pre-defined sticker packs
   - Custom sticker creation
   - Sticker favorites

3. **File Compression**
   - Compress images before upload
   - Reduce video file sizes
   - Optimize audio quality

4. **Message Reactions**
   - Emoji reactions to messages
   - Reaction animations

5. **Message Forwarding**
   - Forward media to other chats
   - Bulk forwarding

## Security Notes

1. **Authentication Required**: All uploads require authenticated users
2. **File Size Limits**: Enforced in Storage rules
3. **File Type Validation**: Both client and server-side
4. **Quota Management**: Monitor Firebase console for usage
5. **Rate Limiting**: Consider implementing if needed

## Support

If you encounter issues:
1. Check Firebase Console logs
2. Verify security rules are deployed
3. Test with Firebase Emulator first
4. Check Flutter doctor for package issues
