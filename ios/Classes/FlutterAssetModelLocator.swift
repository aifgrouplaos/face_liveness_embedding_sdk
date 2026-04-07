import Foundation

enum FlutterAssetModelLocator {
  static func resolveModelPath(
    customPath: String?,
    assetName: String,
    assetResolver: (String) -> String
  ) throws -> String {
    if let customPath, !customPath.isEmpty, FileManager.default.fileExists(atPath: customPath) {
      return customPath
    }

    let assetKey = assetResolver(assetName)
    let candidates = candidatePaths(for: assetKey)
    if let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) {
      return path
    }

    throw NSError(
      domain: "FaceRecognitionSdk",
      code: -1,
      userInfo: [
        NSLocalizedDescriptionKey: "Unable to locate model asset at \(assetName). Checked: \(candidates.joined(separator: ", "))"
      ]
    )
  }

  private static func candidatePaths(for assetKey: String) -> [String] {
    var results: [String] = []
    let normalizedKeys = normalizedAssetKeys(for: assetKey)

    for key in normalizedKeys {
      if let direct = Bundle.main.path(forResource: key, ofType: nil) {
        results.append(direct)
      }
    }

    let bundleRoot = Bundle.main.bundlePath
    for key in normalizedKeys {
      results.append((bundleRoot as NSString).appendingPathComponent(key))
      results.append((bundleRoot as NSString).appendingPathComponent("Frameworks/App.framework/flutter_assets/\(key)"))
      results.append((bundleRoot as NSString).appendingPathComponent("flutter_assets/\(key)"))
    }

    return Array(NSOrderedSet(array: results)) as? [String] ?? results
  }

  private static func normalizedAssetKeys(for assetKey: String) -> [String] {
    var keys = [assetKey]

    if assetKey.hasPrefix("flutter_assets/") == false {
      keys.append("flutter_assets/\(assetKey)")
    }

    if assetKey.hasPrefix("packages/") == false {
      keys.append("packages/face_recognition_sdk/\(assetKey)")
    }

    if assetKey.hasPrefix("flutter_assets/packages/") == false {
      keys.append("flutter_assets/packages/face_recognition_sdk/\(assetKey)")
    }

    return Array(NSOrderedSet(array: keys)) as? [String] ?? keys
  }
}
