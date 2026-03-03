import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radius/features/video_chat/presentation/widgets/call_controls.dart';

void main() {
  testWidgets('renders Next control and triggers callback on tap', (tester) async {
    var nextTapped = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CallControls(
            isMicMuted: false,
            isCameraOff: false,
            onToggleMic: () {},
            onToggleCamera: () {},
            onSwitchCamera: () {},
            onNext: () => nextTapped++,
            onEndCall: () {},
          ),
        ),
      ),
    );

    expect(find.text('Next'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.skip_next_rounded));
    await tester.pump();

    expect(nextTapped, 1);
  });
}
