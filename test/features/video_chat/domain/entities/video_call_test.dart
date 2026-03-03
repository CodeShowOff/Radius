import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radius/features/video_chat/domain/entities/call_status.dart';
import 'package:radius/features/video_chat/domain/entities/video_call.dart';

void main() {
  group('VideoCall.fromJson', () {
    test('parses ISO string timestamps', () {
      final call = VideoCall.fromJson('call-1', {
        'callerId': 'u1',
        'callerName': 'Caller',
        'receiverId': 'u2',
        'receiverName': 'Receiver',
        'status': 'ringing',
        'offer': {'type': 'offer', 'sdp': 'abc'},
        'createdAt': '2026-03-04T10:00:00.000Z',
        'answeredAt': '2026-03-04T10:00:10.000Z',
        'endedAt': '2026-03-04T10:05:00.000Z',
      });

      expect(call.id, 'call-1');
      expect(call.status, CallStatus.ringing);
      expect(call.createdAt.toUtc(), DateTime.parse('2026-03-04T10:00:00.000Z'));
      expect(call.answeredAt?.toUtc(), DateTime.parse('2026-03-04T10:00:10.000Z'));
      expect(call.endedAt?.toUtc(), DateTime.parse('2026-03-04T10:05:00.000Z'));
    });

    test('parses Firestore Timestamp values', () {
      final created = Timestamp.fromDate(DateTime.utc(2026, 3, 4, 10, 0, 0));
      final answered = Timestamp.fromDate(DateTime.utc(2026, 3, 4, 10, 0, 10));

      final call = VideoCall.fromJson('call-2', {
        'callerId': 'u1',
        'callerName': 'Caller',
        'receiverId': 'u2',
        'receiverName': 'Receiver',
        'status': 'connecting',
        'createdAt': created,
        'answeredAt': answered,
      });

      expect(call.status, CallStatus.connecting);
      expect(call.createdAt.toUtc(), DateTime.utc(2026, 3, 4, 10, 0, 0));
      expect(call.answeredAt?.toUtc(), DateTime.utc(2026, 3, 4, 10, 0, 10));
    });

    test('parses epoch-millis integer timestamps', () {
      final createdMillis = DateTime.utc(2026, 3, 4, 10, 0, 0).millisecondsSinceEpoch;
      final endedMillis = DateTime.utc(2026, 3, 4, 10, 5, 0).millisecondsSinceEpoch;

      final call = VideoCall.fromJson('call-3', {
        'callerId': 'u1',
        'callerName': 'Caller',
        'receiverId': 'u2',
        'receiverName': 'Receiver',
        'status': 'ended',
        'createdAt': createdMillis,
        'endedAt': endedMillis,
      });

      expect(call.status, CallStatus.ended);
      expect(call.createdAt.toUtc(), DateTime.utc(2026, 3, 4, 10, 0, 0));
      expect(call.endedAt?.toUtc(), DateTime.utc(2026, 3, 4, 10, 5, 0));
    });
  });
}
