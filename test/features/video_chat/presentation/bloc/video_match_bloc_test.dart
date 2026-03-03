import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:radius/features/video_chat/data/video_match_service.dart';
import 'package:radius/features/video_chat/domain/entities/video_chat_profile.dart';
import 'package:radius/features/video_chat/presentation/bloc/video_match_bloc.dart';

class MockVideoMatchService extends Mock implements VideoMatchService {}

void main() {
  late MockVideoMatchService mockMatchService;
  StreamController<Map<String, dynamic>?>? queueController;

  final profile = VideoChatProfile(
    userId: 'user-1',
    displayName: 'Tester',
    photoUrl: null,
    createdAt: DateTime(2026, 3, 4),
    updatedAt: DateTime(2026, 3, 4),
  );

  setUp(() {
    mockMatchService = MockVideoMatchService();
    queueController = null;
    when(() => mockMatchService.leaveQueue(any())).thenAnswer((_) async {});
  });

  test('initial state is VideoMatchIdle', () {
    final bloc = VideoMatchBloc(matchService: mockMatchService);
    expect(bloc.state, isA<VideoMatchIdle>());
    bloc.close();
  });

  blocTest<VideoMatchBloc, VideoMatchState>(
    'emits [VideoMatchSearching, VideoMatchFound] when queue doc transitions to matched',
    build: () {
      queueController = StreamController<Map<String, dynamic>?>();
      addTearDown(() async => queueController?.close());

      when(() => mockMatchService.joinQueue(
            userId: 'user-1',
            displayName: 'Tester',
            photoUrl: null,
          )).thenAnswer((_) async {});
      when(() => mockMatchService.watchMyQueueDoc('user-1'))
          .thenAnswer((_) => queueController!.stream);
      when(() => mockMatchService.tryMatch(
            myUserId: 'user-1',
            myDisplayName: 'Tester',
            myPhotoUrl: null,
          )).thenAnswer((_) async => true);
      return VideoMatchBloc(matchService: mockMatchService);
    },
    act: (bloc) async {
      bloc.add(VideoMatchStarted(profile: profile));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      queueController!.add({
        'status': 'matched',
        'matchedWith': 'user-2',
        'matchedName': 'Anonymous',
        'matchedPhotoUrl': null,
        'callRole': 'caller',
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
    },
    skip: 0,
    expect: () => [
      isA<VideoMatchSearching>(),
      isA<VideoMatchFound>()
          .having((s) => s.matchedUserId, 'matchedUserId', 'user-2')
          .having((s) => s.matchedName, 'matchedName', 'Anonymous')
          .having((s) => s.callRole, 'callRole', 'caller'),
    ],
    verify: (_) {
      verify(() => mockMatchService.joinQueue(
            userId: 'user-1',
            displayName: 'Tester',
            photoUrl: null,
          )).called(1);
      verify(() => mockMatchService.tryMatch(
            myUserId: 'user-1',
            myDisplayName: 'Tester',
            myPhotoUrl: null,
          )).called(greaterThanOrEqualTo(1));
      verify(() => mockMatchService.leaveQueue('user-1')).called(greaterThanOrEqualTo(1));
    },
  );

  blocTest<VideoMatchBloc, VideoMatchState>(
    'emits [VideoMatchSearching, VideoMatchError] when joinQueue throws',
    build: () {
      when(() => mockMatchService.joinQueue(
            userId: 'user-1',
            displayName: 'Tester',
            photoUrl: null,
          )).thenThrow(Exception('join failed'));

      return VideoMatchBloc(matchService: mockMatchService);
    },
    act: (bloc) => bloc.add(VideoMatchStarted(profile: profile)),
    expect: () => [
      isA<VideoMatchSearching>(),
      isA<VideoMatchError>(),
    ],
  );

  blocTest<VideoMatchBloc, VideoMatchState>(
    'emits [VideoMatchSearching, VideoMatchIdle] when user cancels search',
    build: () {
      when(() => mockMatchService.joinQueue(
            userId: 'user-1',
            displayName: 'Tester',
            photoUrl: null,
          )).thenAnswer((_) async {});
        when(() => mockMatchService.watchMyQueueDoc('user-1'))
          .thenAnswer((_) => const Stream.empty());
      when(() => mockMatchService.tryMatch(
            myUserId: 'user-1',
            myDisplayName: 'Tester',
            myPhotoUrl: null,
          )).thenAnswer((_) async => false);

      return VideoMatchBloc(matchService: mockMatchService);
    },
    act: (bloc) async {
      bloc.add(VideoMatchStarted(profile: profile));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      bloc.add(const VideoMatchCancelled());
    },
    expect: () => [
      isA<VideoMatchSearching>(),
      isA<VideoMatchIdle>(),
    ],
    verify: (_) {
      verify(() => mockMatchService.leaveQueue('user-1')).called(greaterThanOrEqualTo(1));
    },
  );
}
