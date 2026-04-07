import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'face_liveness_embed_sdk_platform_interface.dart';
import 'models/face_frame.dart';
import 'models/face_result.dart';
import 'models/sdk_config.dart';

class MethodChannelFaceLivenessEmbeddingSdk
    extends FaceLivenessEmbeddingSdkPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('face_recognition_sdk');

  @override
  Future<void> initialize(FaceSdkConfig config) async {
    await methodChannel.invokeMethod<void>('initialize', config.toMap());
  }

  @override
  Future<FaceProcessResult> processFrame(FaceFrame frame) async {
    final Map<dynamic, dynamic>? result = await methodChannel
        .invokeMapMethod<dynamic, dynamic>('processFrame', frame.toMap());

    return FaceProcessResult.fromMap(Map<dynamic, dynamic>.from(result ?? {}));
  }

  @override
  Future<FaceEnrollmentResult> enroll(List<FaceFrame> frames) async {
    final payload =
        frames.map((frame) => frame.toMap()).toList(growable: false);
    final Map<dynamic, dynamic>? result = await methodChannel
        .invokeMapMethod<dynamic, dynamic>('enroll', <String, Object?>{
      'frames': payload,
    });

    return FaceEnrollmentResult.fromMap(
      Map<dynamic, dynamic>.from(result ?? {}),
    );
  }

  @override
  Future<FaceVerificationResult> verify(
    FaceFrame frame,
    List<double> referenceEmbedding,
  ) async {
    final Map<dynamic, dynamic>? result = await methodChannel
        .invokeMapMethod<dynamic, dynamic>('verify', <String, Object?>{
      'frame': frame.toMap(),
      'referenceEmbedding': referenceEmbedding,
    });

    return FaceVerificationResult.fromMap(
      Map<dynamic, dynamic>.from(result ?? {}),
    );
  }

  @override
  Future<void> dispose() async {
    await methodChannel.invokeMethod<void>('dispose');
  }
}
