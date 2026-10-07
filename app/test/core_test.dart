import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ucsc_router/core/api_client.dart';
import 'package:ucsc_router/core/format.dart';
import 'package:ucsc_router/core/server_url.dart';

void main() {
  group('time and duration text', () {
    test('clocks are read from the ISO text, not converted', () {
      expect(clockFromIso('2026-10-12T14:40:00-07:00'), '2:40 PM');
      expect(clockFromIso('2026-10-12T00:05:00-07:00'), '12:05 AM');
      expect(clockFromIso('2026-10-12T12:00:00-07:00'), '12:00 PM');
      expect(clockFromIso('2026-12-01T09:05:00-08:00'), '9:05 AM');
      expect(clockFromIso('not a time'), 'not a time');
      expect(clockFromHhmm('08:00'), '8:00 AM');
      expect(clockFromHhmm('16:00'), '4:00 PM');
    });

    test('durations', () {
      expect(durationText(0.2), 'less than a minute');
      expect(durationText(5), '5 min');
      expect(durationText(59.6), '1 h');
      expect(durationText(60), '1 h');
      expect(durationText(95), '1 h 35 min');
    });

    test('weekday of an ISO time', () {
      expect(weekdayFromIso('2026-10-12T14:40:00-07:00'), 'Mon');
      expect(weekdayFromIso('2026-10-14T08:00:00-07:00'), 'Wed');
      expect(weekdayFromIso('nonsense'), '');
    });
  });

  group('server address', () {
    test('is tidied', () {
      expect(normalizeServerUrl('example.onrender.com'), 'https://example.onrender.com');
      expect(normalizeServerUrl('  https://example.com/  '), 'https://example.com');
      expect(normalizeServerUrl('http://10.0.2.2:8000'), 'http://10.0.2.2:8000');
      expect(normalizeServerUrl('https://example.com/api/'), 'https://example.com/api');
    });

    test('nonsense is refused', () {
      for (final bad in ['', '   ', 'has spaces.com', 'ftp://example.com', 'https://', 'https://x.com?a=1']) {
        expect(normalizeServerUrl(bad), isNull, reason: bad);
      }
    });

    test('plain http is only fine on your own network', () {
      expect(isInsecureRemote('https://example.com'), isFalse);
      expect(isInsecureRemote('http://localhost:8000'), isFalse);
      expect(isInsecureRemote('http://10.0.2.2:8000'), isFalse);
      expect(isInsecureRemote('http://192.168.1.20:8000'), isFalse);
      expect(isInsecureRemote('http://172.20.1.1'), isFalse);
      expect(isInsecureRemote('http://example.com'), isTrue);
      expect(isInsecureRemote('http://172.40.1.1'), isTrue);
    });
  });

  group('ApiClient', () {
    ApiClient clientFor(Future<http.Response> Function(http.Request) handler, {Duration? timeout}) =>
        ApiClient(
          baseUrl: 'https://example.com',
          client: MockClient(handler),
          timeout: timeout ?? const Duration(seconds: 5),
        );

    http.Response json(Object body, [int status = 200]) =>
        http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

    test('GET builds the address and decodes the answer', () async {
      late http.Request seen;
      final api = clientFor((r) async {
        seen = r;
        return json({'ok': true});
      });
      expect(await api.getJson('/api/meta', query: {'a': 'b'}), {'ok': true});
      expect(seen.url.toString(), 'https://example.com/api/meta?a=b');
    });

    test('POST sends JSON', () async {
      late http.Request seen;
      final api = clientFor((r) async {
        seen = r;
        return json({'ok': true});
      });
      await api.postJson('/api/today', {'meetings': []});
      expect(seen.method, 'POST');
      expect(seen.headers['Content-Type'], contains('application/json'));
      expect(jsonDecode(seen.body), {'meetings': []});
    });

    test('with no server address it says so, without trying', () {
      final api = ApiClient(baseUrl: '', client: MockClient((r) async => fail('should not be called')));
      expect(
        api.getJson('/x'),
        throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.notConfigured)),
      );
    });

    test("the server's own message is shown for a 4xx", () async {
      final api = clientFor((r) async => json({'error': 'That class is online.'}, 422));
      await expectLater(
        api.postJson('/x', {}),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', 'That class is online.')
            .having((e) => e.kind, 'kind', ApiErrorKind.rejected)),
      );
    });

    test('a 429 carries how long to wait', () async {
      final api = clientFor((r) async => json({'error': 'Slow down.', 'retry_after': 12}, 429));
      await expectLater(
        api.getJson('/x'),
        throwsA(isA<ApiException>()
            .having((e) => e.kind, 'kind', ApiErrorKind.rateLimited)
            .having((e) => e.retryAfterSeconds, 'retry', 12)),
      );
    });

    test('a 5xx or a page that is not JSON becomes a calm message', () async {
      final broken = clientFor((r) async => http.Response('<html>Bad gateway</html>', 502));
      await expectLater(
        broken.getJson('/x'),
        throwsA(isA<ApiException>()
            .having((e) => e.kind, 'kind', ApiErrorKind.server)
            .having((e) => e.message, 'message', contains('502'))),
      );
      final odd = clientFor((r) async => http.Response('hello', 200));
      await expectLater(odd.getJson('/x'), throwsA(isA<ApiException>()));
    });

    test('no connection is reported as offline', () async {
      final api = clientFor((r) async => throw http.ClientException('no route to host'));
      await expectLater(
        api.getJson('/x'),
        throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.offline)),
      );
    });

    test('a slow server (maybe waking up) is reported as a timeout', () async {
      final api = clientFor(
        (r) => Completer<http.Response>().future, // never answers
        timeout: const Duration(milliseconds: 50),
      );
      await expectLater(
        api.getJson('/x'),
        throwsA(isA<ApiException>()
            .having((e) => e.kind, 'kind', ApiErrorKind.timeout)
            .having((e) => e.message, 'message', contains('waking up'))),
      );
    });
  });
}
