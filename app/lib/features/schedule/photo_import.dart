import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The most the server takes: the API accepts 5 MB per image.
const maxPhotoBytes = 5000000;

/// The longest side, in pixels, to try in turn. The API itself reads at about 1,500, so a larger picture only
/// costs upload time.
const photoEdges = [2000, 1400, 1000];

/// A photo ready to send to the server.
class PickedPhoto {
  const PickedPhoto(this.bytes, this.mediaType);

  final Uint8List bytes;
  final String mediaType;
}

/// Picks a photo or screenshot and returns the file's bytes, or null if nothing was chosen. Tests replace this.
final photoPickerProvider = Provider<Future<Uint8List?> Function()>((ref) => pickPhotoBytes);

/// Makes what was picked fit what the server takes (see [preparePhoto]). Tests replace this, since drawing
/// an image runs on the engine's own clock.
final photoPreparerProvider = Provider<Future<PickedPhoto> Function(Uint8List)>((ref) => preparePhoto);

Future<Uint8List?> pickPhotoBytes() async {
  final file = await FilePicker.pickFile(
    type: FileType.image,
    // HEIC from the photo library would be useless to the server, so ask for a JPEG-compatible copy.
    darwinOptions: const DarwinOptions(assetRepresentationMode: DarwinAssetRepresentationMode.compatible),
  );
  return file?.readAsBytes();
}

/// Redraws a picked file as a PNG that fits what the server takes, smaller each time it is still too big.
/// Always redrawing, rather than sending the file as it is, drops what a photo carries besides its picture,
/// such as where it was taken, and turns any format the phone can draw (HEIC, say) into one the server takes.
/// Throws a [FormatException], with a message for the student, if the file is empty, not a picture the phone
/// can read, or still too big at the smallest size.
Future<PickedPhoto> preparePhoto(Uint8List bytes, {int maxBytes = maxPhotoBytes, List<int> edges = photoEdges}) async {
  if (bytes.isEmpty) throw const FormatException('That photo is empty.');
  for (final edge in edges) {
    final png = await _redrawAsPng(bytes, edge);
    if (png.length <= maxBytes) return PickedPhoto(png, 'image/png');
  }
  throw const FormatException('That photo is too large to send. Try a screenshot of just your schedule.');
}

Future<Uint8List> _redrawAsPng(Uint8List bytes, int longestSide) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final wide = descriptor.width >= descriptor.height;
    final shrink = (wide ? descriptor.width : descriptor.height) > longestSide;
    // Decoded at the smaller size, so a very large photo is never held at full size.
    codec = await descriptor.instantiateCodec(
      targetWidth: shrink && wide ? longestSide : null,
      targetHeight: shrink && !wide ? longestSide : null,
    );
    image = (await codec.getNextFrame()).image;
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) throw const FormatException("That file isn't a photo I can read.");
    return png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
  } on FormatException {
    rethrow;
  } on Object {
    throw const FormatException("That file isn't a photo I can read.");
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}
