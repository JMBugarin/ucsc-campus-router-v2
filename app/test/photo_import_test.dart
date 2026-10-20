import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ucsc_router/core/api_client.dart';
import 'package:ucsc_router/features/schedule/photo_import.dart';
import 'package:ucsc_router/features/schedule/schedule_repository.dart';

Future<Uint8List> pngOf(int width, int height, {bool noise = false}) async {
  final pixels = Uint8List(width * height * 4);
  var seed = 7;
  for (var i = 0; i < pixels.length; i += 4) {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    pixels[i] = noise ? seed & 255 : 200;
    pixels[i + 1] = noise ? (seed >> 8) & 255 : 220;
    pixels[i + 2] = noise ? (seed >> 16) & 255 : 255;
    pixels[i + 3] = 255;
  }
  final decoded = Completer<ui.Image>();
  ui.decodeImageFromPixels(pixels, width, height, ui.PixelFormat.rgba8888, decoded.complete);
  final image = await decoded.future;
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// A 2 by 2 bitmap, a format the phone can draw but the server does not take.
Uint8List tinyBmp() {
  final b = ByteData(70);
  b.setUint8(0, 0x42);
  b.setUint8(1, 0x4D);
  b.setUint32(2, 70, Endian.little);
  b.setUint32(10, 54, Endian.little);
  b.setUint32(14, 40, Endian.little);
  b.setInt32(18, 2, Endian.little);
  b.setInt32(22, 2, Endian.little);
  b.setUint16(26, 1, Endian.little);
  b.setUint16(28, 24, Endian.little);
  b.setUint32(34, 16, Endian.little);
  for (var i = 54; i < 70; i++) {
    b.setUint8(i, 0x80);
  }
  return b.buffer.asUint8List();
}

Future<(int, int)> sizeOf(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final image = (await codec.getNextFrame()).image;
  final size = (image.width, image.height);
  image.dispose();
  codec.dispose();
  return size;
}

int crc32(List<int> data) {
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}

List<int> bigEndian32(int value) => [(value >> 24) & 255, (value >> 16) & 255, (value >> 8) & 255, value & 255];

/// The same picture with a text chunk added after the header, the way a camera or an editor adds
/// "where this was taken" to a file.
Uint8List withTextChunk(Uint8List png, String keyword, String text) {
  final data = [...keyword.codeUnits, 0, ...text.codeUnits];
  final type = 'tEXt'.codeUnits;
  final chunk = [...bigEndian32(data.length), ...type, ...data, ...bigEndian32(crc32([...type, ...data]))];
  const afterHeader = 8 + 25; // the signature, then the 25 bytes of the header chunk
  return Uint8List.fromList([...png.sublist(0, afterHeader), ...chunk, ...png.sublist(afterHeader)]);
}

bool isPng(Uint8List bytes) =>
    bytes.length > 8 && const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A].asMap().entries.every((e) => bytes[e.key] == e.value);

void main() {
  group('preparing a photo', () {
    testWidgets('is always a redraw as a PNG, so nothing but the picture is sent', (tester) async {
      await tester.runAsync(() async {
        final plain = await pngOf(40, 30);
        final marked = withTextChunk(plain, 'Location', 'GPS 36.99771,-122.06352');
        expect(String.fromCharCodes(marked), contains('36.99771,-122.06352'), reason: 'the file does carry it');
        expect(isPng(marked), isTrue);

        final prepared = await preparePhoto(marked);
        expect(prepared.mediaType, 'image/png');
        expect(isPng(prepared.bytes), isTrue);
        expect(String.fromCharCodes(prepared.bytes), isNot(contains('36.99771')), reason: 'a drawn picture has no such notes');
        expect(String.fromCharCodes(prepared.bytes), isNot(contains('Location')));
        expect(await sizeOf(prepared.bytes), (40, 30), reason: 'a small picture is not stretched or shrunk');
      });
    });

    testWidgets('nothing at all is refused', (tester) async {
      await tester.runAsync(() async {
        await expectLater(preparePhoto(Uint8List(0)), throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('empty'))));
      });
    });

    testWidgets('a file that is not a picture is refused with a plain message', (tester) async {
      await tester.runAsync(() async {
        final notAnImage = Uint8List.fromList(List.generate(200, (i) => i % 251));
        final fakeJpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(60, 1)]);
        for (final bytes in [notAnImage, fakeJpeg, Uint8List.fromList('%PDF-1.7 hello'.codeUnits)]) {
          await expectLater(
            preparePhoto(bytes),
            throwsA(isA<FormatException>().having((e) => e.message, 'message', contains("isn't a photo I can read"))),
          );
        }
      });
    });

    testWidgets('a picture the phone can draw but the server does not take is sent as a PNG', (tester) async {
      await tester.runAsync(() async {
        final prepared = await preparePhoto(tinyBmp());
        expect(prepared.mediaType, 'image/png');
        expect(isPng(prepared.bytes), isTrue);
        expect(await sizeOf(prepared.bytes), (2, 2));
      });
    });

    testWidgets('a large picture is drawn at the size asked for, keeping its shape', (tester) async {
      await tester.runAsync(() async {
        final wide = await pngOf(3000, 2000);
        final (w, h) = await sizeOf((await preparePhoto(wide)).bytes);
        expect(w, 2000);
        expect(h, closeTo(1333, 1));
        final tall = await pngOf(1000, 3000);
        final (tw, th) = await sizeOf((await preparePhoto(tall)).bytes);
        expect(th, 2000);
        expect(tw, closeTo(667, 1));
      });
    });

    testWidgets('one that is too big is redrawn smaller until it fits', (tester) async {
      await tester.runAsync(() async {
        final big = await pngOf(500, 400, noise: true);
        expect(big.length, greaterThan(400000), reason: 'noise barely compresses');
        final prepared = await preparePhoto(big, maxBytes: 200000, edges: const [300, 150]);
        expect(prepared.mediaType, 'image/png');
        expect(prepared.bytes.length, lessThanOrEqualTo(200000));
        final (w, h) = await sizeOf(prepared.bytes);
        expect((w, h), (150, 120), reason: 'the first size, 300, was still over the limit, and the shape is kept');
      });
    });

    testWidgets('a tall screenshot is shrunk by its height', (tester) async {
      await tester.runAsync(() async {
        final tall = await pngOf(300, 900, noise: true);
        final prepared = await preparePhoto(tall, maxBytes: 150000, edges: const [450, 200]);
        final (w, h) = await sizeOf(prepared.bytes);
        expect(h <= 450 && w < h, isTrue, reason: '$w x $h');
        expect(prepared.bytes.length, lessThanOrEqualTo(150000));
      });
    });

    testWidgets('one that cannot be made small enough is refused', (tester) async {
      await tester.runAsync(() async {
        final big = await pngOf(200, 200, noise: true);
        await expectLater(
          preparePhoto(big, maxBytes: 100, edges: const [100, 50]),
          throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('too large'))),
        );
      });
    });

    test('the limit leaves room under what the server takes', () {
      expect(maxPhotoBytes, lessThan(5 * 1024 * 1024));
      expect(base64Encode(Uint8List(maxPhotoBytes)).length + 100, lessThan(8000000), reason: "the server's request limit");
      expect(photoEdges.first, greaterThan(1568), reason: 'at least what the API reads');
    });
  });

  group('asking the server about photos', () {
    late List<http.Request> seen;

    Future<ApiScheduleRepository> repositoryFor(Future<http.Response> Function(http.Request) handler, {Duration? timeout}) async {
      SharedPreferences.setMockInitialValues({});
      seen = [];
      final api = ApiClient(
        baseUrl: 'https://example.com',
        client: MockClient((r) {
          seen.add(r);
          return handler(r);
        }),
        timeout: timeout ?? const Duration(seconds: 5),
        retryDelays: const [Duration.zero, Duration.zero],
      );
      return ApiScheduleRepository(await SharedPreferences.getInstance(), api);
    }

    http.Response json(Object body, [int status = 200]) =>
        http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

    test('a server that can read photos says so', () async {
      final repo = await repositoryFor((r) async => json({
            'photo': {'ready': true, 'reason': '', 'model': 'claude-opus-5-5'},
          }));
      final support = await repo.photoSupport();
      expect((support.ready, support.reason), (true, ''));
      expect(seen.single.url.path, '/api/capabilities');
    });

    test('one that cannot gives its reason', () async {
      final repo = await repositoryFor((r) async => json({
            'photo': {'ready': false, 'reason': 'No API key: set ANTHROPIC_API_KEY where the server runs.'},
          }));
      final support = await repo.photoSupport();
      expect(support.ready, isFalse);
      expect(support.reason, 'No API key: set ANTHROPIC_API_KEY where the server runs. You can paste your schedule instead.');
    });

    test('the hosted server\'s reason loses its advice about the web demo\'s on-device reader', () async {
      final repo = await repositoryFor((r) async => json({
            'photo': {
              'ready': false,
              'reason': "Reading photos with Claude is turned off on a public server, so strangers can't spend its API key. "
                  'The on-device reader still works.',
              'model': 'claude-opus-5-5',
            },
          }));
      expect(
        (await repo.photoSupport()).reason,
        "Reading photos with Claude is turned off on a public server, so strangers can't spend its API key. "
        'You can paste your schedule instead.',
      );
    });

    test('one that gives no reason still gets a sentence', () async {
      for (final photo in [
        {'ready': false},
        {'ready': false, 'reason': ''},
        {'ready': false, 'reason': 'The on-device reader still works.'},
      ]) {
        final repo = await repositoryFor((r) async => json({'photo': photo}));
        expect((await repo.photoSupport()).reason, "This server can't read photos. You can paste your schedule instead.", reason: '$photo');
      }
    });

    test('an older server with no such page, or a strange answer, is treated as unable', () async {
      final old = await repositoryFor((r) async => json({'error': 'unknown endpoint'}, 404));
      var support = await old.photoSupport();
      expect(support.ready, isFalse);
      expect(support.reason, contains('paste your schedule'));
      final strange = await repositoryFor((r) async => json({'something': 'else'}));
      support = await strange.photoSupport();
      expect(support.ready, isFalse);
    });

    test('a server that cannot be reached is an error, not a "no"', () async {
      final repo = await repositoryFor((r) async => throw http.ClientException('down'));
      await expectLater(repo.photoSupport(), throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.offline)));
    });

    test('the photo goes as base64 with its type, and the answer is read like any import', () async {
      final repo = await repositoryFor((r) async => json({
            'meetings': [
              {
                'course': 'XYZ 10',
                'days': [0, 2, 4],
                'start': '14:40',
                'end': '15:45',
                'location': 'Kresge Acad 3201',
                'start_date': '2026-09-24',
                'end_date': '2026-12-04',
              },
            ],
            'notes': ['From the photo: The last row is blurry.'],
            'locations': [
              {'kind': 'building', 'building_name': 'Kresge College Academic Building', 'room_known': true},
            ],
            'source': 'photo',
          }));
      final bytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);
      final result = await repo.importPhoto(bytes, 'image/png');
      expect(seen.single.method, 'POST');
      expect(seen.single.url.path, '/api/schedule/photo');
      expect(jsonDecode(seen.single.body), {'image': base64Encode(bytes), 'media_type': 'image/png'});
      expect(result.meetings.single.course, 'XYZ 10');
      expect(result.notes.single, contains('blurry'));
    });

    test('a photo gets more time than an ordinary request, since the reading takes a while', () async {
      final slow = await repositoryFor(
        (r) async {
          await Future<void>.delayed(const Duration(milliseconds: 120));
          return json({'meetings': [], 'notes': [], 'locations': []});
        },
        timeout: const Duration(milliseconds: 30),
      );
      expect((await slow.importPhoto(Uint8List.fromList([1, 2, 3]), 'image/png')).meetings, isEmpty);
      await expectLater(slow.clean(const []), throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.timeout)));
      expect(photoTimeout, greaterThan(const Duration(minutes: 3)), reason: 'the server allows its reader up to about three minutes');
    });

    test('a photo is sent once however it fails, because each reading costs money', () async {
      for (final status in [408, 429, 500, 502, 503, 504]) {
        final repo = await repositoryFor((r) async => json({'error': 'The photo reader took too long.'}, status));
        await expectLater(repo.importPhoto(Uint8List.fromList([1]), 'image/png'), throwsA(isA<ApiException>()), reason: '$status');
        expect(seen.length, 1, reason: 'status $status');
      }
    });

    test('nor when it times out', () async {
      var sent = 0;
      final api = ApiClient(
        baseUrl: 'https://example.com',
        client: MockClient((r) {
          sent++;
          return Completer<http.Response>().future;
        }),
        retryDelays: const [Duration.zero, Duration.zero],
      );
      await expectLater(
        api.postJson('/api/schedule/photo', {}, timeout: const Duration(milliseconds: 20)),
        throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.timeout)),
      );
      expect(sent, 1);
    });
  });

  group('what the server says when it cannot read a photo', () {
    ApiClient clientFor(http.Response Function() answer) =>
        ApiClient(baseUrl: 'https://example.com', client: MockClient((r) async => answer()), retryDelays: const []);

    http.Response json(Object body, int status) =>
        http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

    test("the server's own words are shown, not a guess that it is waking up", () async {
      const cases = {
        501: 'No API key: set ANTHROPIC_API_KEY where the server runs, then restart it.',
        502: "The photo reader's answer couldn't be understood. Try again.",
        503: 'The photo reader is unavailable: the server\'s Anthropic account has run out of credit.',
        504: 'The photo reader took too long. Try a clearer or smaller screenshot, or try again.',
      };
      for (final entry in cases.entries) {
        final api = clientFor(() => json({'error': entry.value}, entry.key));
        await expectLater(
          api.postJson('/api/schedule/photo', {}),
          throwsA(isA<ApiException>()
              .having((e) => e.message, 'message', entry.value)
              .having((e) => e.statusCode, 'status', entry.key)),
          reason: '${entry.key}',
        );
      }
    });

    test('a host that is waking up, which sends a page of its own, still gets the waking-up message', () async {
      for (final status in [502, 503, 504]) {
        final api = clientFor(() => http.Response('<html>Service Unavailable</html>', status));
        await expectLater(
          api.postJson('/api/schedule/photo', {}),
          throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('waking up'))),
          reason: '$status',
        );
      }
    });

    test('a plain 500 keeps its calm message, whatever detail came with it', () async {
      final api = clientFor(() => json({'error': 'engine failed: boom'}, 500));
      await expectLater(
        api.postJson('/x', {}),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', allOf(contains('500'), isNot(contains('boom'))))),
      );
    });
  });
}
