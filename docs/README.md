# face_recognition_sdk

Flutter plugin SDK for processing face input into embeddings and verification results on Android and iOS.

## What This SDK Does

This SDK is a reusable processing layer for multiple apps.

It can:

- process face input frames
- detect and validate one face with Google ML Kit
- apply a practical real-face gate before embedding extraction
- generate a normalized `192`-dimensional face embedding with `MobileFaceNet`
- enroll a stable reference embedding from multiple accepted frames
- compare a live embedding with a caller-provided reference embedding in real time

It does not:

- store face embeddings
- store users or identity records
- implement clock-in / clock-out workflows
- manage backend sync or business logic

## Current Direction

The SDK is being aligned to this processing flow:

1. Capture camera frame in Flutter
2. Send frame data to the native plugin
3. Detect one face with Google ML Kit
4. Validate quality, pose, centering, and stability
5. Apply the real-face gate
6. If accepted, preprocess the face crop
7. Run `MobileFaceNet`
8. Return embedding and optional verification result

## Core API

```dart
final sdk = FaceRecognitionSdk();

await sdk.initialize(
  const FaceSdkConfig(
    matchThreshold: 0.58,
  ),
);

final enrollment = await sdk.enroll(frames);
final referenceEmbedding = enrollment.embedding;

final verification = await sdk.verify(frame, referenceEmbedding);
```

## Intended Use

The SDK is generic.

Host apps can use it for:

- attendance or check-in flows
- employee verification
- re-authentication
- other face-match decisions

The host app is responsible for storing the enrolled reference embedding and deciding what a `match` means.

## Example App

The example app is intended to demonstrate generic enroll and verify behavior with a live camera stream.

The example should show:

- face detection state
- face-gate state
- embedding readiness
- verification score
- match / no-match result

## Current Work Remaining

- align all public docs to the new processing-only SDK direction
- simplify the public API away from anti-spoof-specific settings
- refactor Android gate logic around ML Kit-derived rules
- migrate iOS face detection from `Vision` to Google ML Kit
- refresh the example app to generic enroll / verify terminology
- calibrate match thresholds on target devices

## Notes

- `enroll()` stays in the SDK as a processing convenience method
- the SDK returns embeddings but does not persist them
- the current long-term plan is documented in `docs/IMPLEMENTATION_PLAN.md`

## References

- `docs/IMPLEMENTATION_PLAN.md`
- `docs/CALIBRATION_CHECKLIST.md`
- `docs/STATUS_MEANINGS.md`
