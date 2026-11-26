import 'package:flutter_test/flutter_test.dart';
import 'package:kinly/state/node_controller.dart';
import 'package:kinly/util/format.dart';

void main() {
  group('formatCallDuration', () {
    test('formats minutes and seconds as mm:ss', () {
      expect(
        formatCallDuration(const Duration(minutes: 2, seconds: 5)),
        '02:05',
      );
    });

    test('formats hours and minutes as h:mm:ss', () {
      expect(
        formatCallDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '01:02:03',
      );
    });
  });

  group('CallState', () {
    test('an outgoing call starts in the outgoing phase', () {
      final call = CallState(
        peer: 'peer-device',
        callId: 'call-1',
        isIncoming: false,
        video: false,
      );
      expect(call.phase, CallPhase.outgoing);
      expect(call.isIncomingCall, isFalse);
      expect(call.isOngoing, isFalse);
    });

    test('an incoming call starts in the incoming phase', () {
      final call = CallState(
        peer: 'peer-device',
        callId: 'call-1',
        isIncoming: true,
        video: true,
      );
      expect(call.phase, CallPhase.incoming);
      expect(call.isIncomingCall, isTrue);
    });

    test('the phase moves to ongoing once the answer arrives', () {
      final call = CallState(
        peer: 'peer-device',
        callId: 'call-1',
        isIncoming: false,
        video: false,
      );
      call.phase = CallPhase.ongoing;
      expect(call.isOngoing, isTrue);
      expect(call.error, isNull);
    });

    test('an ended call stops the call flow', () {
      final call = CallState(
        peer: 'peer-device',
        callId: 'call-1',
        isIncoming: false,
        video: false,
      );
      call.phase = CallPhase.ended;
      expect(call.phase, CallPhase.ended);
    });
  });
}
