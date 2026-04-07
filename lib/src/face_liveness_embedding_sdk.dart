import 'package:face_recognition_sdk/src/face_liveness_embed_sdk_platform_interface.dart';
import 'package:face_recognition_sdk/src/models/face_frame.dart';
import 'package:face_recognition_sdk/src/models/face_result.dart';
import 'package:face_recognition_sdk/src/models/sdk_config.dart';

class FaceLivenessEmbeddingSdk {
  const FaceLivenessEmbeddingSdk();

  Future<void> initialize(FaceSdkConfig config) {
    return FaceLivenessEmbeddingSdkPlatform.instance.initialize(config);
  }

  Future<FaceProcessResult> processFrame(FaceFrame frame) {
    return FaceLivenessEmbeddingSdkPlatform.instance.processFrame(frame);
  }

  Future<FaceEnrollmentResult> enroll(List<FaceFrame> frames) {
    return FaceLivenessEmbeddingSdkPlatform.instance.enroll(frames);
  }

  Future<FaceVerificationResult> verify(
    FaceFrame frame,
    List<double> referenceEmbedding,
  ) {
    return FaceLivenessEmbeddingSdkPlatform.instance.verify(
      frame,
      referenceEmbedding,
    );
  }

  Future<void> dispose() {
    return FaceLivenessEmbeddingSdkPlatform.instance.dispose();
  }
}
