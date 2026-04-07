class FaceSdkConfig {
  const FaceSdkConfig({
    this.matchThreshold = 0.58,
    this.faceModelAsset = 'model/mobile_face_net.tflite',
    this.faceModelPath,
    this.minFaceSize = 160,
    this.stableFrameCount = 3,
    this.inferenceIntervalMs = 120,
    this.maxYaw = 15,
    this.maxPitch = 15,
    this.maxRoll = 15,
    this.blurThreshold = 90,
  });

  final double matchThreshold;
  final String faceModelAsset;
  final String? faceModelPath;
  final int minFaceSize;
  final int stableFrameCount;
  final int inferenceIntervalMs;
  final double maxYaw;
  final double maxPitch;
  final double maxRoll;
  final double blurThreshold;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'matchThreshold': matchThreshold,
      'faceModelAsset': faceModelAsset,
      'faceModelPath': faceModelPath,
      'minFaceSize': minFaceSize,
      'stableFrameCount': stableFrameCount,
      'inferenceIntervalMs': inferenceIntervalMs,
      'maxYaw': maxYaw,
      'maxPitch': maxPitch,
      'maxRoll': maxRoll,
      'blurThreshold': blurThreshold,
    };
  }
}
