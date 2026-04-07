import CoreGraphics
import UIKit

struct PreprocessedFace {
  let embeddingInput: [Float]
  let blurScore: Double
  let cropWidth: Int
  let cropHeight: Int
  let embeddingInputSize: Int
}

final class FacePreprocessor {
  func preprocess(
    image: CGImage,
    faceRect: CGRect,
    roll: CGFloat,
    embeddingSize: Int = 112
  ) -> PreprocessedFace? {
    guard let cropped = cropFace(from: image, faceRect: faceRect) else {
      return nil
    }

    let aligned = rotate(image: cropped, radians: -roll) ?? cropped
    guard let embeddingImage = resize(image: aligned, width: embeddingSize, height: embeddingSize) else {
      return nil
    }

    return PreprocessedFace(
      embeddingInput: normalizedRGB(from: embeddingImage, signedUnit: true),
      blurScore: computeBlurScore(image: embeddingImage),
      cropWidth: aligned.width,
      cropHeight: aligned.height,
      embeddingInputSize: embeddingSize * embeddingSize * 3
    )
  }

  private func cropFace(from image: CGImage, faceRect: CGRect) -> CGImage? {
    let width = CGFloat(image.width)
    let height = CGFloat(image.height)
    let side = max(faceRect.width, faceRect.height) * 1.35
    let center = CGPoint(x: faceRect.midX, y: faceRect.midY - faceRect.height * 0.08)
    var rect = CGRect(
      x: center.x - side / 2,
      y: center.y - side / 2,
      width: side,
      height: side
    )
    rect.origin.x = max(0, rect.origin.x)
    rect.origin.y = max(0, rect.origin.y)
    rect.size.width = min(width - rect.origin.x, rect.size.width)
    rect.size.height = min(height - rect.origin.y, rect.size.height)
    let integral = rect.integral
    guard integral.width > 1, integral.height > 1 else {
      return nil
    }
    return image.cropping(to: integral)
  }

  private func rotate(image: CGImage, radians: CGFloat) -> CGImage? {
    if abs(radians) < 0.0001 {
      return image
    }

    let originalRect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    let transform = CGAffineTransform(rotationAngle: radians)
    let rotatedRect = originalRect.applying(transform).integral
    let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()

    guard let context = CGContext(
      data: nil,
      width: Int(rotatedRect.width),
      height: Int(rotatedRect.height),
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
      return nil
    }

    context.translateBy(x: rotatedRect.width / 2, y: rotatedRect.height / 2)
    context.rotate(by: radians)
    context.draw(image, in: CGRect(x: -originalRect.width / 2, y: -originalRect.height / 2, width: originalRect.width, height: originalRect.height))
    return context.makeImage()
  }

  private func resize(image: CGImage, width: Int, height: Int) -> CGImage? {
    let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
      return nil
    }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
  }

  private func computeBlurScore(image: CGImage) -> Double {
    let width = image.width
    let height = image.height
    guard width > 2, height > 2 else {
      return 0
    }

    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
    let colorSpace = CGColorSpaceCreateDeviceRGB()

    guard let context = CGContext(
      data: &pixels,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: bytesPerRow,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
      return 0
    }

    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    var grayscale = [Double](repeating: 0, count: width * height)
    for y in 0..<height {
      for x in 0..<width {
        let index = y * bytesPerRow + x * bytesPerPixel
        let r = Double(pixels[index])
        let g = Double(pixels[index + 1])
        let b = Double(pixels[index + 2])
        grayscale[y * width + x] = 0.299 * r + 0.587 * g + 0.114 * b
      }
    }

    var laplacians: [Double] = []
    laplacians.reserveCapacity((width - 2) * (height - 2))
    for y in 1..<(height - 1) {
      for x in 1..<(width - 1) {
        let center = grayscale[y * width + x]
        let top = grayscale[(y - 1) * width + x]
        let bottom = grayscale[(y + 1) * width + x]
        let left = grayscale[y * width + (x - 1)]
        let right = grayscale[y * width + (x + 1)]
        laplacians.append(4 * center - top - bottom - left - right)
      }
    }

    guard !laplacians.isEmpty else {
      return 0
    }

    let mean = laplacians.reduce(0, +) / Double(laplacians.count)
    let variance = laplacians.reduce(0) { partial, value in
      let delta = value - mean
      return partial + (delta * delta)
    } / Double(laplacians.count)
    return variance
  }

  private func normalizedRGB(from image: CGImage, signedUnit: Bool) -> [Float] {
    let width = image.width
    let height = image.height
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
    let colorSpace = CGColorSpaceCreateDeviceRGB()

    guard let context = CGContext(
      data: &pixels,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: bytesPerRow,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
      return []
    }

    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    var output = [Float]()
    output.reserveCapacity(width * height * 3)

    for y in 0..<height {
      for x in 0..<width {
        let index = y * bytesPerRow + x * bytesPerPixel
        let r = Float(pixels[index])
        let g = Float(pixels[index + 1])
        let b = Float(pixels[index + 2])
        if signedUnit {
          output.append((r / 127.5) - 1)
          output.append((g / 127.5) - 1)
          output.append((b / 127.5) - 1)
        } else {
          output.append(r / 255)
          output.append(g / 255)
          output.append(b / 255)
        }
      }
    }

    return output
  }
}
