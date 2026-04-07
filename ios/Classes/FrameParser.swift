import Flutter
import UIKit

struct ParsedFrame {
  let width: Int
  let height: Int
  let rotationDegrees: Int
  let image: CGImage
  let uiImage: UIImage
}

enum FrameParserError: LocalizedError {
  case missingField(String)
  case unsupportedFormat(String)
  case invalidImageData(String)

  var errorDescription: String? {
    switch self {
    case .missingField(let field):
      return "Frame \(field) is required."
    case .unsupportedFormat(let format):
      return "iOS processFrame currently supports \(format)."
    case .invalidImageData(let message):
      return message
    }
  }
}

final class FrameParser {
  func parse(frame: [String: Any]) throws -> ParsedFrame {
    guard let width = frame["width"] as? NSNumber else {
      throw FrameParserError.missingField("width")
    }
    guard let height = frame["height"] as? NSNumber else {
      throw FrameParserError.missingField("height")
    }
    guard let rotation = frame["rotationDegrees"] as? NSNumber else {
      throw FrameParserError.missingField("rotationDegrees")
    }
    guard let format = frame["format"] as? String else {
      throw FrameParserError.missingField("format")
    }

    switch format {
    case "bgra8888":
      guard let planes = frame["planes"] as? [[String: Any]], let plane = planes.first else {
        throw FrameParserError.missingField("planes")
      }
      guard let typedData = plane["bytes"] as? FlutterStandardTypedData else {
        throw FrameParserError.invalidImageData("BGRA frame bytes are missing.")
      }
      let bytesPerRow = (plane["bytesPerRow"] as? NSNumber)?.intValue ?? width.intValue * 4
      guard let image = cgImageFromBGRA(
        data: typedData.data,
        width: width.intValue,
        height: height.intValue,
        bytesPerRow: bytesPerRow
      ) else {
        throw FrameParserError.invalidImageData("Unable to decode BGRA frame.")
      }
      return ParsedFrame(
        width: width.intValue,
        height: height.intValue,
        rotationDegrees: rotation.intValue,
        image: rotatedImage(image, degrees: rotation.intValue) ?? image,
        uiImage: UIImage(cgImage: rotatedImage(image, degrees: rotation.intValue) ?? image)
      )
    case "jpeg":
      guard let planes = frame["planes"] as? [[String: Any]], let plane = planes.first,
            let typedData = plane["bytes"] as? FlutterStandardTypedData,
            let image = UIImage(data: typedData.data)?.cgImage
      else {
        throw FrameParserError.invalidImageData("JPEG frame bytes are missing.")
      }
      return ParsedFrame(
        width: image.width,
        height: image.height,
        rotationDegrees: rotation.intValue,
        image: rotatedImage(image, degrees: rotation.intValue) ?? image,
        uiImage: UIImage(cgImage: rotatedImage(image, degrees: rotation.intValue) ?? image)
      )
    default:
      throw FrameParserError.unsupportedFormat("bgra8888 and jpeg only")
    }
  }

  private func cgImageFromBGRA(data: Data, width: Int, height: Int, bytesPerRow: Int) -> CGImage? {
    let cfData = data as CFData
    guard let provider = CGDataProvider(data: cfData) else {
      return nil
    }
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    return CGImage(
      width: width,
      height: height,
      bitsPerComponent: 8,
      bitsPerPixel: 32,
      bytesPerRow: bytesPerRow,
      space: colorSpace,
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue),
      provider: provider,
      decode: nil,
      shouldInterpolate: true,
      intent: .defaultIntent
    )
  }

  private func rotatedImage(_ image: CGImage, degrees: Int) -> CGImage? {
    let normalized = ((degrees % 360) + 360) % 360
    guard normalized != 0 else {
      return image
    }

    let radians = CGFloat(normalized) * .pi / 180
    let size = CGSize(width: image.width, height: image.height)
    let rect = CGRect(origin: .zero, size: size).applying(CGAffineTransform(rotationAngle: radians)).integral
    let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()

    guard let context = CGContext(
      data: nil,
      width: Int(rect.width),
      height: Int(rect.height),
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
      return nil
    }

    context.translateBy(x: rect.width / 2, y: rect.height / 2)
    context.rotate(by: radians)
    context.draw(image, in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
    return context.makeImage()
  }
}
