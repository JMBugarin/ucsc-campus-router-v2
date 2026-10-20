import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'recognized_text.dart';

/// Something that went wrong choosing or reading a picture, in words for the student.
class PictureException implements Exception {
  const PictureException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Reads the text in a picture on this phone. Nothing is sent anywhere.
abstract class TextRecognizer {
  /// Throws a [PictureException] if the file can't be read as a picture or can't be recognized.
  Future<RecognizedText> recognize(String path);
}

const _visionChannel = MethodChannel('ucsc_router/text_recognition');

/// Apple's Vision framework, through the app's own platform channel.
class VisionTextRecognizer implements TextRecognizer {
  const VisionTextRecognizer({this.channel = _visionChannel, this.timeout = const Duration(seconds: 90)});

  final MethodChannel channel;
  final Duration timeout;

  @override
  Future<RecognizedText> recognize(String path) async {
    try {
      final reply = await channel.invokeMethod<Object>('recognize', {'path': path}).timeout(timeout);
      return RecognizedText.fromJson(reply);
    } on PlatformException catch (e) {
      throw PictureException(switch (e.code) {
        'unreadable' => "That file isn't a picture I can read.",
        'too_large' => 'That picture is too large to read. Try a screenshot of just your schedule.',
        _ => "I couldn't read that picture. Try a clearer screenshot.",
      });
    } on MissingPluginException {
      throw const PictureException(
        "Reading pictures isn't available on this device. You can paste your schedule instead.",
      );
    } on TimeoutException {
      throw const PictureException('Reading that picture took too long. Try a smaller screenshot.');
    } on FormatException {
      throw const PictureException("I couldn't read that picture. Try a clearer screenshot.");
    }
  }
}

/// Text recognition where the app has none.
class UnsupportedTextRecognizer implements TextRecognizer {
  const UnsupportedTextRecognizer();

  @override
  Future<RecognizedText> recognize(String path) => Future.error(
    const PictureException("Reading pictures isn't available on this device. You can paste your schedule instead."),
  );
}

/// Whether this build can read a picture of a schedule: only on iOS so far.
final pictureImportAvailableProvider = Provider<bool>((ref) => Platform.isIOS);

final textRecognizerProvider = Provider<TextRecognizer>(
  (ref) => ref.watch(pictureImportAvailableProvider) ? const VisionTextRecognizer() : const UnsupportedTextRecognizer(),
);
