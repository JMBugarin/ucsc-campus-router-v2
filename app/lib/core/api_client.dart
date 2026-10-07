import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Why a request to the server failed, so the screens can say something useful.
enum ApiErrorKind {
  /// No server address has been entered yet.
  notConfigured,

  /// The phone could not reach the server at all.
  offline,

  /// The server took too long (a sleeping free host can need a minute to wake).
  timeout,

  /// Too many requests; try again after [ApiException.retryAfterSeconds].
  rateLimited,

  /// The server understood the request and said no (its message is safe to show).
  rejected,

  /// The server failed or answered something unexpected.
  server,
}

class ApiException implements Exception {
  const ApiException(
    this.message, {
    this.kind = ApiErrorKind.server,
    this.statusCode,
    this.retryAfterSeconds,
  });

  final String message;
  final ApiErrorKind kind;
  final int? statusCode;
  final int? retryAfterSeconds;

  @override
  String toString() => message;
}

/// A thin JSON client for the campus router server.
class ApiClient {
  ApiClient({
    required this.baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 60),
  }) : _client = client ?? http.Client();

  /// Like `https://example.onrender.com`, with no trailing slash. Empty means "not set up yet".
  final String baseUrl;
  final Duration timeout;
  final http.Client _client;

  bool get isConfigured => baseUrl.isNotEmpty;

  // `async` so that a problem such as "no server address yet" arrives as a failed future,
  // the same way every other failure does, instead of being thrown on the spot.
  Future<Map<String, dynamic>> getJson(String path, {Map<String, String>? query}) async {
    final uri = _uri(path, query);
    return _send(() => _client.get(uri, headers: {'Accept': 'application/json'}));
  }

  Future<Map<String, dynamic>> postJson(String path, Map<String, dynamic> body) async {
    final uri = _uri(path);
    return _send(() => _client.post(
          uri,
          headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
          body: jsonEncode(body),
        ));
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    if (!isConfigured) {
      throw const ApiException(
        'Enter your server address in Settings first.',
        kind: ApiErrorKind.notConfigured,
      );
    }
    return Uri.parse('$baseUrl$path').replace(queryParameters: query);
  }

  Future<Map<String, dynamic>> _send(Future<http.Response> Function() request) async {
    final http.Response response;
    try {
      response = await request().timeout(timeout);
    } on TimeoutException {
      throw const ApiException(
        'The server is taking a long time to answer. If it has been idle it may be waking up, '
        'so try again in a minute.',
        kind: ApiErrorKind.timeout,
      );
    } on http.ClientException {
      throw const ApiException(
        "Can't reach the server. Check your connection and the server address in Settings.",
        kind: ApiErrorKind.offline,
      );
    } on FormatException {
      throw const ApiException('The server address looks wrong. Check it in Settings.',
          kind: ApiErrorKind.notConfigured);
    }
    return _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic>? body;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) body = decoded;
    } on FormatException {
      body = null;
    }

    final status = response.statusCode;
    if (status >= 200 && status < 300) {
      if (body == null) {
        throw ApiException("The server's answer wasn't understood.", statusCode: status);
      }
      return body;
    }

    final message = body?['error'];
    if (status == 429) {
      final retry = body?['retry_after'];
      throw ApiException(
        message is String ? message : 'Too many requests. Please slow down.',
        kind: ApiErrorKind.rateLimited,
        statusCode: status,
        retryAfterSeconds: retry is int ? retry : null,
      );
    }
    if (status >= 400 && status < 500 && message is String) {
      throw ApiException(message, kind: ApiErrorKind.rejected, statusCode: status);
    }
    throw ApiException(
      'The server had a problem (status $status). Try again in a moment.',
      statusCode: status,
    );
  }

  void close() => _client.close();
}
