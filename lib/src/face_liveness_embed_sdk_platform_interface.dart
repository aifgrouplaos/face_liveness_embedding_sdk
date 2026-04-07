import 'package:face_recognition_sdk/src/face_liveness_embed_sdk_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'models/face_frame.dart';
import 'models/face_result.dart';
import 'models/sdk_config.dart';

abstract class FaceLivenessEmbeddingSdkPlatform extends PlatformInterface {
  FaceLivenessEmbeddingSdkPlatform() : super(token: _token);

  static final Object _token = Object();

  static FaceLivenessEmbeddingSdkPlatform _instance =
      MethodChannelFaceLivenessEmbeddingSdk();

  static FaceLivenessEmbeddingSdkPlatform get instance => _instance;

  static set instance(FaceLivenessEmbeddingSdkPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<void> initialize(FaceSdkConfig config) {
    throw UnimplementedError('initialize() has not been implemented.');
  }

  Future<FaceProcessResult> processFrame(FaceFrame frame) {
    throw UnimplementedError('processFrame() has not been implemented.');
  }

  Future<FaceEnrollmentResult> enroll(List<FaceFrame> frames) {
    throw UnimplementedError('enroll() has not been implemented.');
  }

  Future<FaceVerificationResult> verify(
    FaceFrame frame,
    List<double> referenceEmbedding,
  ) {
    throw UnimplementedError('verify() has not been implemented.');
  }

  Future<void> dispose() {
    throw UnimplementedError('dispose() has not been implemented.');
  }
}
