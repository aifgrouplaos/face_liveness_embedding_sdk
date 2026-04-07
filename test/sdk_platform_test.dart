import 'dart:typed_data';

import 'package:face_recognition_sdk/face_liveness_embedding_sdk.dart';
import 'package:face_recognition_sdk/src/face_liveness_embed_sdk_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

void main() {
  group('FaceLivenessEmbeddingSdk delegation', () {
    late FakeFaceLivenessEmbeddingSdkPlatform fakePlatform;
    late FaceLivenessEmbeddingSdkPlatform originalPlatform;
    const sdk = FaceLivenessEmbeddingSdk();
    final frame = FaceFrame(
      width: 112,
      height: 112,
      rotationDegrees: 0,
      format: FaceImageFormat.bgra8888,
      planes: <FaceFramePlane>[
        FaceFramePlane(
          bytes: Uint8List.fromList(List<int>.filled(16, 1)),
          bytesPerRow: 8,
          bytesPerPixel: 4,
          width: 2,
          height: 2,
        ),
      ],
      timestampMillis: 123,
      cameraFacing: 'front',
    );
    const config = FaceSdkConfig(
      matchThreshold: 0.6,
    );

    setUp(() {
      originalPlatform = FaceLivenessEmbeddingSdkPlatform.instance;
      fakePlatform = FakeFaceLivenessEmbeddingSdkPlatform();
      FaceLivenessEmbeddingSdkPlatform.instance = fakePlatform;
    });

    tearDown(() {
      FaceLivenessEmbeddingSdkPlatform.instance = originalPlatform;
    });

    test('forwards initialize and dispose', () async {
      await sdk.initialize(config);
      await sdk.dispose();

      expect(fakePlatform.initializedWith?.matchThreshold, 0.6);
      expect(fakePlatform.disposeCalled, isTrue);
    });

    test('forwards processFrame', () async {
      final result = await sdk.processFrame(frame);

      expect(fakePlatform.processedFrames.single.width, 112);
      expect(result.status, 'processed');
      expect(result.embedding, hasLength(192));
    });

    test('forwards verify', () async {
      final result = await sdk.verify(frame, List<double>.filled(192, 0.2));

      expect(fakePlatform.verifyFrame?.height, 112);
      expect(fakePlatform.verifyReferenceEmbedding, hasLength(192));
      expect(result.isMatch, isTrue);
      expect(result.score, closeTo(0.87, 0.0001));
    });

    test('forwards enroll', () async {
      final result = await sdk.enroll(<FaceFrame>[frame, frame]);

      expect(fakePlatform.enrollFrames, hasLength(2));
      expect(result.acceptedFrames, 2);
      expect(result.embedding, hasLength(192));
    });
  });
}

class FakeFaceLivenessEmbeddingSdkPlatform
    extends FaceLivenessEmbeddingSdkPlatform with MockPlatformInterfaceMixin {
  FaceSdkConfig? initializedWith;
  bool disposeCalled = false;
  final List<FaceFrame> processedFrames = <FaceFrame>[];
  FaceFrame? verifyFrame;
  List<double>? verifyReferenceEmbedding;
  List<FaceFrame>? enrollFrames;

  @override
  Future<void> initialize(FaceSdkConfig config) async {
    initializedWith = config;
  }

  @override
  Future<void> dispose() async {
    disposeCalled = true;
  }

  @override
  Future<FaceProcessResult> processFrame(FaceFrame frame) async {
    processedFrames.add(frame);
    return FaceProcessResult.fromMap(<String, Object?>{
      'status': 'processed',
      'failureReason': null,
      'embedding': List<double>.filled(192, 0.1),
      'boundingBox': <String, double>{
        'left': 1,
        'top': 2,
        'right': 3,
        'bottom': 4,
      },
      'quality': <String, Object?>{
        'hasSingleFace': true,
        'isCentered': true,
        'poseValid': true,
        'isStable': true,
        'isBlurred': false,
      },
      'faceGate': <String, Object?>{
        'isReal': true,
        'status': 'passed',
      },
    });
  }

  @override
  Future<FaceVerificationResult> verify(
    FaceFrame frame,
    List<double> referenceEmbedding,
  ) async {
    verifyFrame = frame;
    verifyReferenceEmbedding = referenceEmbedding;
    return FaceVerificationResult.fromMap(<String, Object?>{
      'status': 'verified',
      'failureReason': null,
      'embedding': List<double>.filled(192, 0.2),
      'score': 0.87,
      'isMatch': true,
      'isReal': true,
      'faceGateStatus': 'passed',
    });
  }

  @override
  Future<FaceEnrollmentResult> enroll(List<FaceFrame> frames) async {
    enrollFrames = frames;
    return FaceEnrollmentResult.fromMap(<String, Object?>{
      'status': 'enrolled',
      'failureReason': null,
      'acceptedFrames': frames.length,
      'embedding': List<double>.filled(192, 0.3),
    });
  }
}
