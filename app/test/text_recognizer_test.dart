import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ucsc_router/features/schedule/ocr/text_recognizer.dart';

const channel = MethodChannel('ucsc_router/text_recognition');

void answer(Future<Object?> Function(MethodCall call)? handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, handler);
}

Future<PictureException> failure(Future<Object?> future) async {
  try {
    await future;
  } on PictureException catch (e) {
    return e;
  }
  fail('expected a PictureException');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => answer(null));

  group('VisionTextRecognizer', () {
    test('sends the path and reads the reply', () async {
      MethodCall? received;
      answer((call) async {
        received = call;
        return {
          'width': 1290,
          'height': 2796,
          'lines': [
            {'text': 'CSE 101', 'confidence': 0.98, 'x': 0.1, 'y': 0.1, 'w': 0.2, 'h': 0.02, 'words': []},
          ],
        };
      });
      final text = await const VisionTextRecognizer().recognize('/tmp/schedule.png');
      expect(received?.method, 'recognize');
      expect(received?.arguments, {'path': '/tmp/schedule.png'});
      expect(text.lines.single.text, 'CSE 101');
      expect(text.height, 2796);
    });

    test(
      'says what is wrong with a file that is not a picture, a picture that is too big, and any other failure',
      () async {
        final messages = <String, String>{};
        for (final code in ['unreadable', 'too_large', 'failed', 'something_new']) {
          answer((call) async => throw PlatformException(code: code, message: 'raw $code detail'));
          messages[code] = (await failure(const VisionTextRecognizer().recognize('/x'))).message;
        }
        expect(messages['unreadable'], contains("isn't a picture"));
        expect(messages['too_large'], contains('too large'));
        expect(messages['failed'], contains('clearer screenshot'));
        expect(messages['something_new'], messages['failed']);
        for (final message in messages.values) {
          expect(message, isNot(contains('raw')), reason: "the platform's own wording is not shown");
        }
      },
    );

    test('a device without the channel says reading pictures is not available', () async {
      answer(null);
      final error = await failure(const VisionTextRecognizer().recognize('/x'));
      expect(error.message, contains("isn't available on this device"));
      expect(error.message, contains('paste'));
    });

    test('a reply that is the wrong shape is a failed reading, not a crash', () async {
      answer((call) async => {'width': 0, 'height': 10, 'lines': []});
      expect((await failure(const VisionTextRecognizer().recognize('/x'))).message, contains('clearer screenshot'));
      answer((call) async => null);
      expect((await failure(const VisionTextRecognizer().recognize('/x'))).message, contains('clearer screenshot'));
    });

    test('gives up on a reading that never finishes', () async {
      answer((call) => Completer<Object?>().future);
      final error = await failure(const VisionTextRecognizer(timeout: Duration(milliseconds: 30)).recognize('/x'));
      expect(error.message, contains('too long'));
    });
  });

  group('what the app uses', () {
    test('iOS gets Vision, anything else says it is unavailable', () async {
      final ios = ProviderContainer(overrides: [pictureImportAvailableProvider.overrideWithValue(true)]);
      final other = ProviderContainer(overrides: [pictureImportAvailableProvider.overrideWithValue(false)]);
      addTearDown(ios.dispose);
      addTearDown(other.dispose);
      expect(ios.read(textRecognizerProvider), isA<VisionTextRecognizer>());
      final unsupported = other.read(textRecognizerProvider);
      expect(unsupported, isA<UnsupportedTextRecognizer>());
      expect((await failure(unsupported.recognize('/x'))).message, contains("isn't available"));
    });
  });
}
