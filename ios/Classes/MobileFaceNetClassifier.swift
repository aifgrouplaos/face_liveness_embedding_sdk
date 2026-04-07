import Foundation
import TensorFlowLite

struct EmbeddingPrediction {
  let embedding: [Double]
  let failureReason: String?
}

final class MobileFaceNetClassifier {
  private let assetResolver: (String) -> String
  private var interpreter: Interpreter?
  private var lastError: String?

  init(assetResolver: @escaping (String) -> String) {
    self.assetResolver = assetResolver
  }

  func configure(configuration: [String: Any]) {
    interpreter = nil
    lastError = nil

    let assetName = (configuration["faceModelAsset"] as? String) ?? "model/mobile_face_net.tflite"
    let customPath = configuration["faceModelPath"] as? String

    do {
      let modelPath = try resolveModelPath(customPath: customPath, assetName: assetName)
      var options = Interpreter.Options()
      options.threadCount = 2
      let interpreter = try Interpreter(modelPath: modelPath, options: options)
      try interpreter.allocateTensors()
      self.interpreter = interpreter
    } catch {
      lastError = error.localizedDescription
    }
  }

  func extractEmbedding(input: [Float]) -> EmbeddingPrediction {
    guard let interpreter else {
      return EmbeddingPrediction(
        embedding: [],
        failureReason: lastError ?? "MobileFaceNet model is not available."
      )
    }

    do {
      let inputTensor = try interpreter.input(at: 0)
      let expectedElements = inputTensor.shape.dimensions.dropFirst().reduce(1, *)
      guard expectedElements == input.count else {
        return EmbeddingPrediction(
          embedding: [],
          failureReason: "MobileFaceNet input size \(input.count) does not match expected size \(expectedElements)."
        )
      }

      let inputData = TensorDataConverter.data(from: input)
      try interpreter.copy(inputData, toInputAt: 0)
      try interpreter.invoke()

      let outputTensor = try interpreter.output(at: 0)
      let values = TensorDataConverter.array(from: outputTensor.data, as: Float32.self)
      let normalized = l2Normalize(values).map(Double.init)
      return EmbeddingPrediction(embedding: normalized, failureReason: nil)
    } catch {
      return EmbeddingPrediction(embedding: [], failureReason: error.localizedDescription)
    }
  }

  private func resolveModelPath(customPath: String?, assetName: String) throws -> String {
    try FlutterAssetModelLocator.resolveModelPath(
      customPath: customPath,
      assetName: assetName,
      assetResolver: assetResolver
    )
  }

  private func l2Normalize(_ values: [Float]) -> [Float] {
    let norm = sqrt(values.reduce(Float(0)) { $0 + ($1 * $1) })
    guard norm > 0 else {
      return values
    }
    return values.map { $0 / norm }
  }
}
