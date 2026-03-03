import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:radius/features/video_chat/data/video_call_service.dart';
import 'package:radius/features/video_chat/data/webrtc_service.dart';
import 'package:radius/features/video_chat/domain/entities/video_chat_profile.dart';
import 'package:radius/features/video_chat/presentation/bloc/video_call_bloc.dart';

class MockVideoCallService extends Mock implements VideoCallService {}

class MockWebRtcService extends Mock implements WebRtcService {}

void main() {
  late MockVideoCallService mockCallService;
  late MockWebRtcService mockWebRtcService;

  final profile = VideoChatProfile(
    userId: 'me',
    displayName: 'Me',
    photoUrl: null,
    createdAt: DateTime(2026, 3, 4),
    updatedAt: DateTime(2026, 3, 4),
  );

  setUp(() {
    mockCallService = MockVideoCallService();
    mockWebRtcService = MockWebRtcService();

    when(() => mockWebRtcService.initialize()).thenAnswer((_) async {});
    when(() => mockWebRtcService.createOffer())
        .thenAnswer((_) async => RTCSessionDescription('offer-sdp', 'offer'));
    when(() => mockWebRtcService.dispose()).thenAnswer((_) async {});

    when(() => mockCallService.createCall(
          callerId: any(named: 'callerId'),
          callerName: any(named: 'callerName'),
          callerPhotoUrl: any(named: 'callerPhotoUrl'),
          receiverId: any(named: 'receiverId'),
          receiverName: any(named: 'receiverName'),
          receiverPhotoUrl: any(named: 'receiverPhotoUrl'),
          offer: any(named: 'offer'),
        )).thenAnswer((_) async => 'call-1');

    when(() => mockCallService.watchCall('call-1'))
        .thenAnswer((_) => const Stream.empty());
    when(() => mockCallService.watchIceCandidates(
          callId: 'call-1',
          myUserId: 'me',
        )).thenAnswer((_) => const Stream.empty());

    when(() => mockCallService.endCall('call-1')).thenAnswer((_) async {});
    when(() => mockCallService.cleanupCall('call-1')).thenAnswer((_) async {});
    when(() => mockCallService.markConnected('call-1')).thenAnswer((_) async {});
    when(() => mockCallService.addIceCandidate(
          callId: any(named: 'callId'),
          from: any(named: 'from'),
          candidate: any(named: 'candidate'),
        )).thenAnswer((_) async {});
  });

  test('initial state is VideoCallIdle', () {
    final bloc = VideoCallBloc(
      callService: mockCallService,
      webRtcService: mockWebRtcService,
    );
    expect(bloc.state, isA<VideoCallIdle>());
    bloc.close();
  });

  blocTest<VideoCallBloc, VideoCallState>(
    'emits VideoCallError when initiating call without profile',
    build: () => VideoCallBloc(
      callService: mockCallService,
      webRtcService: mockWebRtcService,
    ),
    act: (bloc) => bloc.add(const VideoCallInitiated(
      receiverId: 'user-2',
      receiverName: 'Anon',
    )),
    expect: () => [
      isA<VideoCallError>().having((s) => s.message, 'message', 'Profile not set up'),
    ],
  );

  blocTest<VideoCallBloc, VideoCallState>(
    'emits [VideoCallSettingUp, VideoCallRinging] for successful caller initiation',
    build: () {
      final bloc = VideoCallBloc(
        callService: mockCallService,
        webRtcService: mockWebRtcService,
      );
      bloc.setMyProfile(profile);
      return bloc;
    },
    act: (bloc) => bloc.add(const VideoCallInitiated(
      receiverId: 'user-2',
      receiverName: 'Anon',
    )),
    expect: () => [
      isA<VideoCallSettingUp>(),
      isA<VideoCallRinging>().having((s) => s.callId, 'callId', 'call-1'),
    ],
    verify: (_) {
      verify(() => mockWebRtcService.initialize()).called(1);
      verify(() => mockWebRtcService.createOffer()).called(1);
      verify(() => mockCallService.createCall(
            callerId: 'me',
            callerName: 'Me',
            callerPhotoUrl: null,
            receiverId: 'user-2',
            receiverName: 'Anon',
            receiverPhotoUrl: null,
            offer: any(named: 'offer'),
          )).called(1);
    },
  );

  blocTest<VideoCallBloc, VideoCallState>(
    'emits ended state when active caller ends the call',
    build: () {
      final bloc = VideoCallBloc(
        callService: mockCallService,
        webRtcService: mockWebRtcService,
      );
      bloc.setMyProfile(profile);
      return bloc;
    },
    act: (bloc) async {
      bloc.add(const VideoCallInitiated(
        receiverId: 'user-2',
        receiverName: 'Anon',
      ));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      bloc.add(const VideoCallEnded());
    },
    wait: const Duration(milliseconds: 30),
    expect: () => [
      isA<VideoCallSettingUp>(),
      isA<VideoCallRinging>(),
      isA<VideoCallEndedState>().having((s) => s.reason, 'reason', 'Call ended'),
    ],
    verify: (_) {
      verify(() => mockCallService.endCall('call-1')).called(greaterThanOrEqualTo(1));
      verify(() => mockWebRtcService.dispose()).called(greaterThanOrEqualTo(1));
    },
  );
}
