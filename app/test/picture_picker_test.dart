import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ucsc_router/features/schedule/ocr/picture_picker.dart';
import 'package:ucsc_router/features/schedule/ocr/text_recognizer.dart';

Future<PictureException> failure(Future<Object?> future) async {
  try {
    await future;
  } on PictureException catch (e) {
    return e;
  }
  fail('expected a PictureException');
}

void main() {
  group('SystemPicturePicker', () {
    test('returns the chosen path, or null when the picker is closed', () async {
      expect(await SystemPicturePicker(choose: () async => '/cache/shot.png').pick(), '/cache/shot.png');
      expect(await SystemPicturePicker(choose: () async => null).pick(), isNull);
    });

    test('a photo only in iCloud is explained, any other picker failure is a plain message', () async {
      final icloud = await failure(
        SystemPicturePicker(choose: () async => throw PlatformException(code: 'load_failed')).pick(),
      );
      expect(icloud.message, contains('iCloud'));
      final other = await failure(
        SystemPicturePicker(
          choose: () async => throw PlatformException(code: 'boom', message: 'secret detail'),
        ).pick(),
      );
      expect(other.message, "Couldn't open your photos. Try again.");
      final unexpected = await failure(SystemPicturePicker(choose: () async => throw StateError('x')).pick());
      expect(unexpected.message, "Couldn't open your photos. Try again.");
    });

    test('a pick with no usable path is refused', () async {
      expect((await failure(SystemPicturePicker(choose: () async => '').pick())).message, contains('another'));
    });
  });
}
