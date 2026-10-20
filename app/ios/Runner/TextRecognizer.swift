import Flutter
import ImageIO
import UIKit
import Vision

/// Reads the text in a picture on the device and answers the app's `recognize` calls with each line's
/// text, confidence and position. The picture is read from the path it is given and is never sent anywhere.
final class TextRecognizer {
  static let channelName = "ucsc_router/text_recognition"

  private static let longestSide = 4096
  private static let maxPixels = 120_000_000

  private let queue = DispatchQueue(label: "ucsc_router.text_recognition", qos: .userInitiated)

  static func register(with messenger: FlutterBinaryMessenger) {
    let recognizer = TextRecognizer()
    FlutterMethodChannel(name: channelName, binaryMessenger: messenger).setMethodCallHandler { call, result in
      recognizer.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "recognize" else { return result(FlutterMethodNotImplemented) }
    guard let args = call.arguments as? [String: Any], let path = args["path"] as? String else {
      return result(RecognitionError.unreadable.flutterError)
    }
    queue.async {
      let reply: Any
      do {
        reply = try self.recognize(path: path)
      } catch let error as RecognitionError {
        reply = error.flutterError
      } catch {
        reply = FlutterError(code: "failed", message: error.localizedDescription, details: nil)
      }
      DispatchQueue.main.async { result(reply) }
    }
  }

  private func recognize(path: String) throws -> [String: Any] {
    let image = try loadImage(path: path)
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = ["en-US"]
    try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
    let lines = (request.results ?? []).compactMap(Self.describe)
    return ["width": image.width, "height": image.height, "lines": lines]
  }

  /// Decodes at no more than `longestSide` pixels, so a very large photo is never held at full size, with
  /// its orientation applied so the text is upright.
  private func loadImage(path: String) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
      CGImageSourceGetCount(source) > 0,
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int,
      width > 0, height > 0
    else { throw RecognitionError.unreadable }
    guard width * height <= Self.maxPixels else { throw RecognitionError.tooLarge }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: min(max(width, height), Self.longestSide),
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
      throw RecognitionError.unreadable
    }
    return image
  }

  private static func describe(_ observation: VNRecognizedTextObservation) -> [String: Any]? {
    guard let candidate = observation.topCandidates(1).first else { return nil }
    var line = box(observation.boundingBox)
    line["text"] = candidate.string
    line["confidence"] = Double(candidate.confidence)
    line["words"] = words(of: candidate)
    return line
  }

  /// Vision's origin is the bottom left; the app's is the top left.
  private static func box(_ rect: CGRect) -> [String: Any] {
    ["x": Double(rect.minX), "y": Double(1 - rect.maxY), "w": Double(rect.width), "h": Double(rect.height)]
  }

  private static func words(of candidate: VNRecognizedText) -> [[String: Any]] {
    let text = candidate.string
    var found: [[String: Any]] = []
    var wordStart: String.Index?

    func close(at end: String.Index) {
      guard let start = wordStart else { return }
      wordStart = nil
      guard let rect = (try? candidate.boundingBox(for: start..<end))?.boundingBox else { return }
      var word = box(rect)
      word["text"] = String(text[start..<end])
      found.append(word)
    }

    for index in text.indices {
      if text[index].isWhitespace {
        close(at: index)
      } else if wordStart == nil {
        wordStart = index
      }
    }
    close(at: text.endIndex)
    return found
  }
}

private enum RecognitionError: Error {
  case unreadable
  case tooLarge

  var flutterError: FlutterError {
    switch self {
    case .unreadable:
      return FlutterError(code: "unreadable", message: "That file is not a picture that can be read.", details: nil)
    case .tooLarge:
      return FlutterError(code: "too_large", message: "That picture is too large to read.", details: nil)
    }
  }
}
