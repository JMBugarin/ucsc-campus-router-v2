import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'text_recognizer.dart';

/// Lets the student choose a screenshot or photo from their photo library.
abstract class PicturePicker {
  /// The path of the chosen picture, or null if the picker was closed without choosing.
  /// Throws a [PictureException] if the photo library can't be opened or the photo can't be loaded.
  Future<String?> pick();

  /// Removes the copy of the picture the picker made, once it has been read.
  Future<void> release();
}

Future<String?> _chooseImagePath() async => (await FilePicker.pickFile(type: FileType.image))?.path;

/// The system photo picker, which shows only what the student chooses and needs no photo permission.
class SystemPicturePicker implements PicturePicker {
  const SystemPicturePicker({this.choose = _chooseImagePath});

  /// Opens the picker and returns the chosen file's path. Tests replace this.
  final Future<String?> Function() choose;

  @override
  Future<String?> pick() async {
    final String? path;
    try {
      path = await choose();
    } on PlatformException catch (e) {
      throw PictureException(
        e.code == 'load_failed'
            ? "Couldn't load that photo. If it is stored in iCloud, connect to the internet so it can download, or choose a screenshot saved on this phone."
            : "Couldn't open your photos. Try again.",
      );
    } on Object {
      throw const PictureException("Couldn't open your photos. Try again.");
    }
    if (path != null && path.isEmpty) throw const PictureException("Couldn't open that photo. Try another.");
    return path;
  }

  @override
  Future<void> release() async {
    try {
      await FilePicker.clearTemporaryFiles();
    } on Object {
      // a leftover copy in the app's cache is not worth interrupting the student for
    }
  }
}

final picturePickerProvider = Provider<PicturePicker>((ref) => const SystemPicturePicker());
