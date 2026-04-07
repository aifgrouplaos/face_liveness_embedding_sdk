import Flutter
import MLKitFaceDetection
import MLKitVision
import UIKit

public class FaceRecognitionSdkPlugin: NSObject, FlutterPlugin {
  private var configuration: [String: Any] = [:]
  private let frameParser = FrameParser()
  private let facePreprocessor = FacePreprocessor()
  private let mobileFaceNetClassifier: MobileFaceNetClassifier
  private let faceDetector: FaceDetector

  override init() {
    let options = FaceDetectorOptions()
    options.performanceMode = .fast
    options.landmarkMode = .all
    options.classificationMode = .none
    options.contourMode = .none
    options.isTrackingEnabled = true
    faceDetector = FaceDetector.faceDetector(options: options)
    mobileFaceNetClassifier = MobileFaceNetClassifier(assetResolver: { $0 })
    super.init()
  }

  init(assetResolver: @escaping (String) -> String) {
    let options = FaceDetectorOptions()
    options.performanceMode = .fast
    options.landmarkMode = .all
    options.classificationMode = .none
    options.contourMode = .none
    options.isTrackingEnabled = true
    faceDetector = FaceDetector.faceDetector(options: options)
    mobileFaceNetClassifier = MobileFaceNetClassifier(assetResolver: assetResolver)
    super.init()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "face_recognition_sdk", binaryMessenger: registrar.messenger())
    let instance = FaceRecognitionSdkPlugin(assetResolver: {
      let packageKey = registrar.lookupKey(forAsset: $0, fromPackage: "face_recognition_sdk")
      if packageKey.isEmpty == false {
        return packageKey
      }
      return registrar.lookupKey(forAsset: $0)
    })
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "initialize":
      configuration = call.arguments as? [String: Any] ?? [:]
      mobileFaceNetClassifier.configure(configuration: configuration)
      result(nil)
    case "processFrame":
      handleProcessFrame(call, result: result)
    case "enroll":
      handleEnroll(call, result: result)
    case "verify":
      handleVerify(call, result: result)
    case "dispose":
      configuration = [:]
      mobileFaceNetClassifier.configure(configuration: configuration)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func handleProcessFrame(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let frame = call.arguments as? [String: Any] else {
      result(defaultProcessResult(status: "invalid_argument", failureReason: "Frame payload is missing."))
      return
    }

    let parsedFrame: ParsedFrame
    do {
      parsedFrame = try frameParser.parse(frame: frame)
    } catch {
      result(defaultProcessResult(status: "unsupported_format", failureReason: error.localizedDescription))
      return
    }

    analyzeFrame(parsedFrame) { analysis in
      result(analysis.toProcessMap())
    }
  }

  private func handleVerify(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any] else {
      result(defaultVerificationResult(failureReason: "Verification payload is missing."))
      return
    }
    guard let frame = arguments["frame"] as? [String: Any] else {
      result(defaultVerificationResult(failureReason: "Frame payload is missing."))
      return
    }
    let referenceEmbedding = (arguments["referenceEmbedding"] as? [Any])?
      .compactMap { ($0 as? NSNumber)?.doubleValue } ?? []
    guard !referenceEmbedding.isEmpty else {
      result(defaultVerificationResult(failureReason: "Reference embedding is missing."))
      return
    }

    let parsedFrame: ParsedFrame
    do {
      parsedFrame = try frameParser.parse(frame: frame)
    } catch {
      result(defaultVerificationResult(status: "unsupported_format", failureReason: error.localizedDescription))
      return
    }

    analyzeFrame(parsedFrame) { analysis in
      result(analysis.toVerificationMap(referenceEmbedding: referenceEmbedding, threshold: self.configDouble("matchThreshold", defaultValue: 0.58)))
    }
  }

  private func handleEnroll(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any] else {
      result(defaultEnrollmentResult(failureReason: "Enrollment payload is missing."))
      return
    }
    guard let frames = arguments["frames"] as? [[String: Any]], !frames.isEmpty else {
      result(defaultEnrollmentResult(failureReason: "Enrollment frames are missing."))
      return
    }

    let parsedFrames: [ParsedFrame]
    do {
      parsedFrames = try frames.map { try frameParser.parse(frame: $0) }
    } catch {
      result(defaultEnrollmentResult(status: "unsupported_format", failureReason: error.localizedDescription))
      return
    }

    let group = DispatchGroup()
    let queue = DispatchQueue(label: "face_recognition_sdk.enroll", attributes: .concurrent)
    let syncQueue = DispatchQueue(label: "face_recognition_sdk.enroll.sync")
    var analyses: [FrameAnalysisResult] = []

    for parsedFrame in parsedFrames {
      group.enter()
      queue.async {
        self.analyzeFrame(parsedFrame) { analysis in
          syncQueue.async {
            analyses.append(analysis)
            group.leave()
          }
        }
      }
    }

    group.notify(queue: .main) {
      let accepted = analyses.filter { $0.failureReason == nil && !$0.embedding.isEmpty }
      guard !accepted.isEmpty else {
        let failureReason = analyses.compactMap { $0.failureReason }.first ?? "No valid live face frames were accepted for enrollment."
        result(self.defaultEnrollmentResult(status: "enrollment_failed", failureReason: failureReason))
        return
      }

      let averagedEmbedding = self.averageEmbeddings(accepted.map { $0.embedding })
      result([
        "status": "enrolled",
        "failureReason": NSNull(),
        "acceptedFrames": accepted.count,
        "embedding": averagedEmbedding,
      ])
    }
  }

  private func analyzeFrame(_ parsedFrame: ParsedFrame, completion: @escaping (FrameAnalysisResult) -> Void) {
    let visionImage = VisionImage(image: parsedFrame.uiImage)
    faceDetector.process(visionImage) { faces, error in
      if let error {
        completion(FrameAnalysisResult(status: "detector_error", failureReason: error.localizedDescription))
        return
      }

      let analysis = self.buildFrameAnalysisResult(frame: parsedFrame, faces: faces ?? [])
      completion(analysis)
    }
  }

  private func buildFrameAnalysisResult(frame: ParsedFrame, faces: [Face]) -> FrameAnalysisResult {
    if faces.isEmpty {
      return FrameAnalysisResult(status: "no_face", failureReason: "No face detected.")
    }

    if faces.count > 1 {
      return FrameAnalysisResult(
        status: "multiple_faces",
        failureReason: "Multiple faces detected. Please keep only one face in frame."
      )
    }

    guard let face = faces.first else {
      return FrameAnalysisResult(status: "no_face", failureReason: "No face detected.")
    }

    let boundingBox = face.frame
    let centerX = boundingBox.midX
    let centerY = boundingBox.midY
    let centered = abs(centerX - CGFloat(frame.image.width) / 2) <= CGFloat(frame.image.width) * 0.2 &&
      abs(centerY - CGFloat(frame.image.height) / 2) <= CGFloat(frame.image.height) * 0.2
    let minFaceSize = CGFloat(configInt("minFaceSize", defaultValue: 160))
    let sizeValid = boundingBox.width >= minFaceSize && boundingBox.height >= minFaceSize
    let rollDegrees = Double(abs(face.hasHeadEulerAngleZ ? face.headEulerAngleZ : 0))
    let yawDegrees = Double(abs(face.hasHeadEulerAngleY ? face.headEulerAngleY : 0))
    let maxRollDegrees = configDouble("maxRoll", defaultValue: 15)
    let maxYawDegrees = configDouble("maxYaw", defaultValue: 15)
    let poseValid = rollDegrees <= maxRollDegrees && yawDegrees <= maxYawDegrees
    let landmarks = buildLandmarks(from: face)
    let preprocessing = sizeValid && centered && poseValid && !landmarks.isEmpty
      ? facePreprocessor.preprocess(image: frame.image, faceRect: boundingBox, roll: CGFloat(face.hasHeadEulerAngleZ ? face.headEulerAngleZ : 0) * .pi / 180)
      : nil
    let blurScore = preprocessing?.blurScore ?? 0
    let isBlurred = preprocessing != nil && blurScore < configDouble("blurThreshold", defaultValue: 90)
    let embeddingPrediction: EmbeddingPrediction = {
      guard let preprocessing, !isBlurred else {
        return EmbeddingPrediction(embedding: [], failureReason: nil)
      }
      return mobileFaceNetClassifier.extractEmbedding(input: preprocessing.embeddingInput)
    }()

    let failureReason: String? = {
      if !sizeValid { return "Face is too small. Move closer to the camera." }
      if !centered { return "Face is not centered in frame." }
      if !poseValid {
        return String(
          format: "Face pose is outside the allowed range. Yaw %.1f/%.1f, roll %.1f/%.1f.",
          yawDegrees,
          maxYawDegrees,
          rollDegrees,
          maxRollDegrees
        )
      }
      if landmarks.isEmpty { return "Face landmarks are not sufficiently visible." }
      if preprocessing == nil { return "Face preprocessing failed." }
      if isBlurred { return "Face image is too blurry. Hold the camera steady." }
      if let failureReason = embeddingPrediction.failureReason { return failureReason }
      return nil
    }()
    let faceGateStatus = (preprocessing != nil && !isBlurred && failureReason == nil) ? "passed" : "not_real"

    return FrameAnalysisResult(
      status: failureReason == nil ? "ready_for_embedding" : ((preprocessing != nil && !isBlurred) ? "not_real" : "invalid_face"),
      failureReason: failureReason,
      embedding: embeddingPrediction.embedding,
      boundingBox: [
        "left": boundingBox.minX,
        "top": boundingBox.minY,
        "right": boundingBox.maxX,
        "bottom": boundingBox.maxY,
      ],
      landmarks: landmarks,
      quality: [
        "hasSingleFace": true,
        "isCentered": centered,
        "poseValid": poseValid,
        "isStable": true,
        "isBlurred": isBlurred,
      ],
      faceGate: [
        "isReal": failureReason == nil,
        "status": faceGateStatus,
      ],
      preprocessing: [
        "cropWidth": preprocessing?.cropWidth ?? 0,
        "cropHeight": preprocessing?.cropHeight ?? 0,
        "embeddingInputSize": preprocessing?.embeddingInputSize ?? 0,
        "blurScore": blurScore,
      ]
    )
  }

  private func buildLandmarks(
    from face: Face
  ) -> [[String: Any]] {
    let mappings: [(String, FaceLandmarkType)] = [
      ("leftEye", .leftEye),
      ("rightEye", .rightEye),
      ("noseBase", .noseBase),
      ("leftMouth", .mouthLeft),
      ("rightMouth", .mouthRight),
    ]

    return mappings.compactMap { name, type in
      guard let landmark = face.landmark(ofType: type) else {
        return nil
      }
      return [
        "type": name,
        "x": landmark.position.x,
        "y": landmark.position.y,
      ]
    }
  }

  private func configDouble(_ key: String, defaultValue: Double) -> Double {
    if let value = configuration[key] as? NSNumber {
      return value.doubleValue
    }
    return defaultValue
  }

  private func configInt(_ key: String, defaultValue: Int) -> Int {
    if let value = configuration[key] as? NSNumber {
      return value.intValue
    }
    return defaultValue
  }

  private func defaultProcessResult(
    status: String = "not_ready",
    failureReason: String = "Native frame processing is not implemented yet."
  ) -> [String: Any] {
    return [
      "status": status,
      "failureReason": failureReason,
      "embedding": [],
      "boundingBox": NSNull(),
      "landmarks": [],
      "quality": [
        "hasSingleFace": false,
        "isCentered": false,
        "poseValid": false,
        "isStable": false,
        "isBlurred": false,
      ],
      "faceGate": [
        "isReal": false,
        "status": "unknown",
      ],
    ]
  }

  private func defaultVerificationResult(
    status: String = "not_ready",
    failureReason: String = "Native verification pipeline is not implemented yet."
  ) -> [String: Any] {
    return [
      "status": status,
      "failureReason": failureReason,
      "embedding": [],
      "score": 0.0,
      "isMatch": false,
      "isReal": false,
      "faceGateStatus": "unknown",
    ]
  }

  private func defaultEnrollmentResult(
    status: String = "not_ready",
    failureReason: String = "Native enrollment pipeline is not implemented yet."
  ) -> [String: Any] {
    return [
      "status": status,
      "failureReason": failureReason,
      "acceptedFrames": 0,
      "embedding": [],
    ]
  }

  private func averageEmbeddings(_ embeddings: [[Double]]) -> [Double] {
    guard let first = embeddings.first, !first.isEmpty else {
      return []
    }
    guard embeddings.allSatisfy({ $0.count == first.count }) else {
      return []
    }

    var averaged = Array(repeating: 0.0, count: first.count)
    for embedding in embeddings {
      for index in embedding.indices {
        averaged[index] += embedding[index]
      }
    }
    for index in averaged.indices {
      averaged[index] /= Double(embeddings.count)
    }

    let norm = sqrt(averaged.reduce(0.0) { $0 + ($1 * $1) })
    guard norm > 0 else {
      return averaged
    }
    return averaged.map { $0 / norm }
  }

  private struct FrameAnalysisResult {
    let status: String
    let failureReason: String?
    let embedding: [Double]
    let boundingBox: [String: Any]?
    let landmarks: [[String: Any]]
    let quality: [String: Any]
    let faceGate: [String: Any]
    let preprocessing: [String: Any]

    init(
      status: String,
      failureReason: String?,
      embedding: [Double] = [],
      boundingBox: [String: Any]? = nil,
      landmarks: [[String: Any]] = [],
      quality: [String: Any] = [
        "hasSingleFace": false,
        "isCentered": false,
        "poseValid": false,
        "isStable": false,
        "isBlurred": false,
      ],
      faceGate: [String: Any] = [
        "isReal": false,
        "status": "unknown",
      ],
      preprocessing: [String: Any] = [:]
    ) {
      self.status = status
      self.failureReason = failureReason
      self.embedding = embedding
      self.boundingBox = boundingBox
      self.landmarks = landmarks
      self.quality = quality
      self.faceGate = faceGate
      self.preprocessing = preprocessing
    }

    func toProcessMap() -> [String: Any] {
      [
        "status": status,
        "failureReason": failureReason ?? NSNull(),
        "embedding": embedding,
        "boundingBox": boundingBox ?? NSNull(),
        "landmarks": landmarks,
        "quality": quality,
        "preprocessing": preprocessing,
        "faceGate": faceGate,
      ]
    }

    func toVerificationMap(referenceEmbedding: [Double], threshold: Double) -> [String: Any] {
      guard failureReason == nil, !embedding.isEmpty else {
        return [
          "status": status,
          "failureReason": failureReason ?? "Embedding is unavailable.",
          "embedding": embedding,
          "score": 0.0,
          "isMatch": false,
          "isReal": faceGate["isReal"] as? Bool ?? false,
          "faceGateStatus": faceGate["status"] as? String ?? "unknown",
        ]
      }

      let score = cosineSimilarity(embedding, referenceEmbedding)
      return [
        "status": score >= threshold ? "verified" : "no_match",
        "failureReason": NSNull(),
        "embedding": embedding,
        "score": score,
        "isMatch": score >= threshold,
        "isReal": faceGate["isReal"] as? Bool ?? false,
        "faceGateStatus": faceGate["status"] as? String ?? "unknown",
      ]
    }

    private func cosineSimilarity(_ left: [Double], _ right: [Double]) -> Double {
      guard !left.isEmpty, left.count == right.count else {
        return 0.0
      }
      var dot = 0.0
      var leftNorm = 0.0
      var rightNorm = 0.0
      for index in left.indices {
        dot += left[index] * right[index]
        leftNorm += left[index] * left[index]
        rightNorm += right[index] * right[index]
      }
      guard leftNorm > 0, rightNorm > 0 else {
        return 0.0
      }
      return dot / (sqrt(leftNorm) * sqrt(rightNorm))
    }
  }
}
