import 'dart:typed_data';

enum FaceImageFormat { yuv420, bgra8888, jpeg, nv21 }

class FaceFramePlane {
  const FaceFramePlane({
    required this.bytes,
    required this.bytesPerRow,
    required this.bytesPerPixel,
    this.width,
    this.height,
  });

  final Uint8List bytes;
  final int bytesPerRow;
  final int? bytesPerPixel;
  final int? width;
  final int? height;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'bytes': bytes,
      'bytesPerRow': bytesPerRow,
      'bytesPerPixel': bytesPerPixel,
      'width': width,
      'height': height,
    };
  }
}

class FaceFrame {
  const FaceFrame({
    required this.width,
    required this.height,
    required this.rotationDegrees,
    required this.format,
    required this.planes,
    this.timestampMillis,
    this.cameraFacing,
  });

  final int width;
  final int height;
  final int rotationDegrees;
  final FaceImageFormat format;
  final List<FaceFramePlane> planes;
  final int? timestampMillis;
  final String? cameraFacing;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'width': width,
      'height': height,
      'rotationDegrees': rotationDegrees,
      'format': format.name,
      'timestampMillis': timestampMillis,
      'cameraFacing': cameraFacing,
      'planes': planes.map((plane) => plane.toMap()).toList(growable: false),
    };
  }
}
