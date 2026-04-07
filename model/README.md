# Model Assets

This directory contains model assets used by the SDK.

## Required Model

- `mobile_face_net.tflite`

The SDK uses this model to generate normalized `192`-dimensional face embeddings.

## Current Model Direction

The SDK now follows a processing-only design:

- Google ML Kit handles face detection and the face gate
- `MobileFaceNet` handles embedding generation
- host apps store any returned embeddings outside the SDK

The SDK no longer requires or loads an anti-spoof model asset.

## Expected Face Model Path

Recommended default:

- `model/mobile_face_net.tflite`

If you keep the model elsewhere, provide a custom path through `FaceSdkConfig`:

```dart
const FaceSdkConfig(
  faceModelPath: '/absolute/path/to/mobile_face_net.tflite',
)
```

## Expected Model Behavior

The current SDK expects a face embedding model that:

- accepts a native-preprocessed RGB face crop
- uses the preprocessing contract implemented by Android and iOS preprocessors
- returns a `192`-dimensional embedding vector

## Notes

- the SDK does not store embeddings internally
- the host app is responsible for storing enrolled reference embeddings
- match behavior should be calibrated using `matchThreshold`
