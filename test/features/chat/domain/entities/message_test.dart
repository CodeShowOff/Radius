import 'package:flutter_test/flutter_test.dart';
import 'package:radius/features/chat/domain/entities/message.dart';

void main() {
  group('Message Entity', () {
    final testDate = DateTime(2024, 1, 1);

    test('should create a valid text Message instance', () {
      final message = Message(
        id: 'msg-123',
        conversationId: 'conv-123',
        senderId: 'user-123',
        text: 'Hello World',
        sentAt: testDate,
      );

      expect(message.id, 'msg-123');
      expect(message.conversationId, 'conv-123');
      expect(message.senderId, 'user-123');
      expect(message.text, 'Hello World');
      expect(message.type, MessageType.text);
      expect(message.status, MessageStatus.sent);
    });

    test('should support value equality', () {
      final message1 = Message(
        id: 'msg-123',
        conversationId: 'conv-123',
        senderId: 'user-123',
        text: 'Hello',
        sentAt: testDate,
      );

      final message2 = Message(
        id: 'msg-123',
        conversationId: 'conv-123',
        senderId: 'user-123',
        text: 'Hello',
        sentAt: testDate,
      );

      expect(message1, equals(message2));
    });

    test('should handle different message types', () {
      final textMessage = Message(
        id: 'msg-1',
        conversationId: 'conv-123',
        senderId: 'user-123',
        text: 'Hello',
        type: MessageType.text,
        sentAt: testDate,
      );

      final imageMessage = Message(
        id: 'msg-2',
        conversationId: 'conv-123',
        senderId: 'user-123',
        text: '',
        type: MessageType.image,
        mediaUrl: 'https://example.com/image.jpg',
        sentAt: testDate,
      );

      final audioMessage = Message(
        id: 'msg-3',
        conversationId: 'conv-123',
        senderId: 'user-123',
        text: '',
        type: MessageType.audio,
        mediaUrl: 'https://example.com/audio.mp3',
        duration: 30,
        sentAt: testDate,
      );

      expect(textMessage.type, MessageType.text);
      expect(imageMessage.type, MessageType.image);
      expect(audioMessage.type, MessageType.audio);
      expect(audioMessage.duration, 30);
    });

    test('should handle different message statuses', () {
      final sendingMessage = Message(
        id: 'msg-1',
        conversationId: 'conv-123',
        senderId: 'user-123',
        text: 'Hello',
        status: MessageStatus.sending,
        sentAt: testDate,
      );

      final sentMessage = Message(
        id: 'msg-2',
        conversationId: 'conv-123',
        senderId: 'user-123',
        text: 'Hello',
        status: MessageStatus.sent,
        sentAt: testDate,
      );

      final deliveredMessage = Message(
        id: 'msg-3',
        conversationId: 'conv-123',
        senderId: 'user-123',
        text: 'Hello',
        status: MessageStatus.delivered,
        deliveredAt: testDate.add(const Duration(seconds: 1)),
        sentAt: testDate,
      );

      final readMessage = Message(
        id: 'msg-4',
        conversationId: 'conv-123',
        senderId: 'user-123',
        text: 'Hello',
        status: MessageStatus.read,
        readAt: testDate.add(const Duration(seconds: 2)),
        sentAt: testDate,
      );

      expect(sendingMessage.status, MessageStatus.sending);
      expect(sentMessage.status, MessageStatus.sent);
      expect(deliveredMessage.status, MessageStatus.delivered);
      expect(readMessage.status, MessageStatus.read);
    });

    test('isSentBy should correctly identify sender', () {
      final message = Message(
        id: 'msg-123',
        conversationId: 'conv-123',
        senderId: 'user-123',
        text: 'Hello',
        sentAt: testDate,
      );

      expect(message.isSentBy('user-123'), true);
      expect(message.isSentBy('user-456'), false);
    });

    test('isRead should return correct value', () {
      final unreadMessage = Message(
        id: 'msg-1',
        conversationId: 'conv-123',
        senderId: 'user-123',
        text: 'Hello',
        sentAt: testDate,
      );

      final readMessage = Message(
        id: 'msg-2',
        conversationId: 'conv-123',
        senderId: 'user-123',
        text: 'Hello',
        status: MessageStatus.read,
        readAt: testDate,
        sentAt: testDate,
      );

      expect(unreadMessage.isRead, false);
      expect(readMessage.isRead, true);
    });

    test('isDelivered should return correct value', () {
      final sentMessage = Message(
        id: 'msg-1',
        conversationId: 'conv-123',
        senderId: 'user-123',
        text: 'Hello',
        status: MessageStatus.sent,
        sentAt: testDate,
      );

      final deliveredMessage = Message(
        id: 'msg-2',
        conversationId: 'conv-123',
        senderId: 'user-123',
        text: 'Hello',
        status: MessageStatus.delivered,
        deliveredAt: testDate,
        sentAt: testDate,
      );

      expect(sentMessage.isDelivered, false);
      expect(deliveredMessage.isDelivered, true);
    });

    test('isMediaMessage should correctly identify media messages', () {
      final textMessage = Message(
        id: 'msg-1',
        conversationId: 'conv-123',
        senderId: 'user-123',
        text: 'Hello',
        type: MessageType.text,
        sentAt: testDate,
      );

      final imageMessage = Message(
        id: 'msg-2',
        conversationId: 'conv-123',
        senderId: 'user-123',
        text: '',
        type: MessageType.image,
        mediaUrl: 'https://example.com/image.jpg',
        sentAt: testDate,
      );

      expect(textMessage.isMediaMessage, false);
      expect(imageMessage.isMediaMessage, true);
    });

    test('should handle media file information', () {
      final imageMessage = Message(
        id: 'msg-123',
        conversationId: 'conv-123',
        senderId: 'user-123',
        text: '',
        type: MessageType.image,
        mediaUrl: 'https://example.com/image.jpg',
        mediaFileName: 'photo.jpg',
        mediaFileSize: 1024000,
        sentAt: testDate,
      );

      expect(imageMessage.mediaUrl, 'https://example.com/image.jpg');
      expect(imageMessage.mediaFileName, 'photo.jpg');
      expect(imageMessage.mediaFileSize, 1024000);
    });

    test('isUploading should detect upload progress', () {
      final uploadingMessage = Message(
        id: 'msg-123',
        conversationId: 'conv-123',
        senderId: 'user-123',
        text: '',
        type: MessageType.image,
        uploadProgress: 0.5,
        sentAt: testDate,
      );

      final uploadedMessage = Message(
        id: 'msg-456',
        conversationId: 'conv-123',
        senderId: 'user-123',
        text: '',
        type: MessageType.image,
        mediaUrl: 'https://example.com/image.jpg',
        uploadProgress: 1.0,
        sentAt: testDate,
      );

      expect(uploadingMessage.isUploading, true);
      expect(uploadedMessage.isUploading, false);
    });

    test('should handle deleted messages', () {
      final message = Message(
        id: 'msg-123',
        conversationId: 'conv-123',
        senderId: 'user-123',
        text: 'This will be deleted',
        isDeleted: true,
        sentAt: testDate,
      );

      expect(message.isDeleted, true);
    });

    test('copyWith should create updated instance', () {
      final message = Message(
        id: 'msg-123',
        conversationId: 'conv-123',
        senderId: 'user-123',
        text: 'Hello',
        status: MessageStatus.sent,
        sentAt: testDate,
      );

      final updatedMessage = message.copyWith(
        status: MessageStatus.delivered,
        deliveredAt: testDate.add(const Duration(seconds: 1)),
      );

      expect(updatedMessage.status, MessageStatus.delivered);
      expect(updatedMessage.deliveredAt, testDate.add(const Duration(seconds: 1)));
      expect(updatedMessage.text, 'Hello'); // unchanged
    });
  });
}
