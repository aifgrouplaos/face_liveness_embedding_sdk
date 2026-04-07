import 'package:face_recognition_sdk/face_liveness_embedding_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FaceSdkConfig', () {
    test('serializes generic processing settings', () {
      const config = FaceSdkConfig(
        matchThreshold: 0.61,
        faceModelAsset: 'model/mobile_face_net.tflite',
        faceModelPath: '/tmp/mobile_face_net.tflite',
        minFaceSize: 144,
        maxYaw: 20,
      );

      final map = config.toMap();

      expect(map['matchThreshold'], 0.61);
      expect(map['faceModelPath'], '/tmp/mobile_face_net.tflite');
      expect(map['minFaceSize'], 144);
      expect(map['maxYaw'], 20.0);
    });
  });

  group('FaceProcessResult', () {
    test('parses embedding, box, and face gate values', () {
      final result = FaceProcessResult.fromMap(<String, Object?>{
        'status': 'ready_for_embedding',
        'failureReason': null,
        'embedding': List<double>.filled(192, 0.25),
        'boundingBox': <String, double>{
          'left': 10,
          'top': 20,
          'right': 110,
          'bottom': 140,
        },
        'landmarks': <Map<String, Object?>>[
          <String, Object?>{'type': 'leftEye', 'x': 30, 'y': 40},
        ],
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

      expect(result.embedding, hasLength(192));
      expect(result.boundingBox?.left, 10);
      expect(result.landmarks.single.type, 'leftEye');
      expect(result.faceGate.isReal, isTrue);
      expect(result.faceGate.status, 'passed');
    });

    test('falls back safely when optional fields are missing', () {
      final result = FaceProcessResult.fromMap(<String, Object?>{
        'status': 'invalid_face',
      });

      expect(result.failureReason, isNull);
      expect(result.embedding, isEmpty);
      expect(result.boundingBox, isNull);
      expect(result.landmarks, isEmpty);
      expect(result.quality.hasSingleFace, isFalse);
      expect(result.faceGate.status, 'unknown');
    });
  });

  group('FaceVerificationResult', () {
    test('parses score and match fields', () {
      final result = FaceVerificationResult.fromMap(<String, Object?>{
        'status': 'verified',
        'failureReason': null,
        'embedding': List<double>.filled(192, 0.1),
        'score': 0.77,
        'isMatch': true,
        'isReal': true,
        'faceGateStatus': 'passed',
      });

      expect(result.embedding, hasLength(192));
      expect(result.isMatch, isTrue);
      expect(result.score, closeTo(0.77, 0.0001));
      expect(result.faceGateStatus, 'passed');
    });

    test('defaults safely with sparse payload', () {
      final result = FaceVerificationResult.fromMap(<String, Object?>{});

      expect(result.status, 'not_ready');
      expect(result.embedding, isEmpty);
      expect(result.isMatch, isFalse);
      expect(result.faceGateStatus, 'unknown');
    });
  });

  group('FaceEnrollmentResult', () {
    test('parses accepted frame count and embedding', () {
      final result = FaceEnrollmentResult.fromMap(<String, Object?>{
        'status': 'enrolled',
        'failureReason': null,
        'acceptedFrames': 5,
        'embedding': List<double>.filled(192, 0.05),
      });

      expect(result.acceptedFrames, 5);
      expect(result.embedding, hasLength(192));
    });

    test('defaults accepted frames to zero', () {
      final result = FaceEnrollmentResult.fromMap(<String, Object?>{});

      expect(result.status, 'not_ready');
      expect(result.acceptedFrames, 0);
      expect(result.embedding, isEmpty);
    });
  });
}
