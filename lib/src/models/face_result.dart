class FaceBoundingBox {
  const FaceBoundingBox({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;

  factory FaceBoundingBox.fromMap(Map<dynamic, dynamic> map) {
    return FaceBoundingBox(
      left: (map['left'] as num?)?.toDouble() ?? 0,
      top: (map['top'] as num?)?.toDouble() ?? 0,
      right: (map['right'] as num?)?.toDouble() ?? 0,
      bottom: (map['bottom'] as num?)?.toDouble() ?? 0,
    );
  }
}

class FaceLandmark {
  const FaceLandmark({required this.type, required this.x, required this.y});

  final String type;
  final double x;
  final double y;

  factory FaceLandmark.fromMap(Map<dynamic, dynamic> map) {
    return FaceLandmark(
      type: map['type'] as String? ?? 'unknown',
      x: (map['x'] as num?)?.toDouble() ?? 0,
      y: (map['y'] as num?)?.toDouble() ?? 0,
    );
  }
}

class FaceQuality {
  const FaceQuality({
    required this.hasSingleFace,
    required this.isCentered,
    required this.poseValid,
    required this.isStable,
    required this.isBlurred,
  });

  final bool hasSingleFace;
  final bool isCentered;
  final bool poseValid;
  final bool isStable;
  final bool isBlurred;

  factory FaceQuality.fromMap(Map<dynamic, dynamic> map) {
    return FaceQuality(
      hasSingleFace: map['hasSingleFace'] as bool? ?? false,
      isCentered: map['isCentered'] as bool? ?? false,
      poseValid: map['poseValid'] as bool? ?? false,
      isStable: map['isStable'] as bool? ?? false,
      isBlurred: map['isBlurred'] as bool? ?? false,
    );
  }

  static const empty = FaceQuality(
    hasSingleFace: false,
    isCentered: false,
    poseValid: false,
    isStable: false,
    isBlurred: false,
  );
}

class FaceGateResult {
  const FaceGateResult({required this.isReal, required this.status});

  final bool isReal;
  final String status;

  factory FaceGateResult.fromMap(Map<dynamic, dynamic> map) {
    return FaceGateResult(
      isReal: map['isReal'] as bool? ?? false,
      status: map['status'] as String? ?? 'unknown',
    );
  }

  static const empty = FaceGateResult(isReal: false, status: 'unknown');
}

class FaceProcessResult {
  const FaceProcessResult({
    required this.status,
    required this.failureReason,
    required this.embedding,
    required this.boundingBox,
    required this.landmarks,
    required this.quality,
    required this.faceGate,
  });

  final String status;
  final String? failureReason;
  final List<double> embedding;
  final FaceBoundingBox? boundingBox;
  final List<FaceLandmark> landmarks;
  final FaceQuality quality;
  final FaceGateResult faceGate;

  factory FaceProcessResult.fromMap(Map<dynamic, dynamic> map) {
    final embeddingValues =
        (map['embedding'] as List<dynamic>? ?? const <dynamic>[])
            .map((value) => (value as num).toDouble())
            .toList(growable: false);
    final landmarks = (map['landmarks'] as List<dynamic>? ?? const <dynamic>[])
        .map(
          (item) =>
              FaceLandmark.fromMap(Map<dynamic, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
    final boxMap = map['boundingBox'];

    return FaceProcessResult(
      status: map['status'] as String? ?? 'not_ready',
      failureReason: map['failureReason'] as String?,
      embedding: embeddingValues,
      boundingBox: boxMap is Map
          ? FaceBoundingBox.fromMap(Map<dynamic, dynamic>.from(boxMap))
          : null,
      landmarks: landmarks,
      quality: map['quality'] is Map
          ? FaceQuality.fromMap(
              Map<dynamic, dynamic>.from(map['quality'] as Map),
            )
          : FaceQuality.empty,
      faceGate: map['faceGate'] is Map
          ? FaceGateResult.fromMap(
              Map<dynamic, dynamic>.from(map['faceGate'] as Map),
            )
          : FaceGateResult.empty,
    );
  }
}

class FaceEnrollmentResult {
  const FaceEnrollmentResult({
    required this.status,
    required this.failureReason,
    required this.acceptedFrames,
    required this.embedding,
  });

  final String status;
  final String? failureReason;
  final int acceptedFrames;
  final List<double> embedding;

  factory FaceEnrollmentResult.fromMap(Map<dynamic, dynamic> map) {
    return FaceEnrollmentResult(
      status: map['status'] as String? ?? 'not_ready',
      failureReason: map['failureReason'] as String?,
      acceptedFrames: map['acceptedFrames'] as int? ?? 0,
      embedding: (map['embedding'] as List<dynamic>? ?? const <dynamic>[])
          .map((value) => (value as num).toDouble())
          .toList(growable: false),
    );
  }
}

class FaceVerificationResult {
  const FaceVerificationResult({
    required this.status,
    required this.failureReason,
    required this.embedding,
    required this.score,
    required this.isMatch,
    required this.isReal,
    required this.faceGateStatus,
  });

  final String status;
  final String? failureReason;
  final List<double> embedding;
  final double score;
  final bool isMatch;
  final bool isReal;
  final String faceGateStatus;

  factory FaceVerificationResult.fromMap(Map<dynamic, dynamic> map) {
    return FaceVerificationResult(
      status: map['status'] as String? ?? 'not_ready',
      failureReason: map['failureReason'] as String?,
      embedding: (map['embedding'] as List<dynamic>? ?? const <dynamic>[])
          .map((value) => (value as num).toDouble())
          .toList(growable: false),
      score: (map['score'] as num?)?.toDouble() ?? 0,
      isMatch: map['isMatch'] as bool? ?? false,
      isReal: map['isReal'] as bool? ?? false,
      faceGateStatus: map['faceGateStatus'] as String? ?? 'unknown',
    );
  }
}
