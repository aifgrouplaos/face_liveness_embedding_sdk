# What We Did So Far

## Goal

Build a Flutter plugin SDK for Android and iOS that processes face input into embeddings and verification results.

The final agreed direction is:

- use Google ML Kit for face detection and the practical real-face gate
- use `MobileFaceNet` for `192`-dimensional face embeddings
- keep `enroll()` so the SDK can generate a stable reference embedding from multiple frames
- use `verify()` to compare a live frame against a caller-provided reference embedding
- keep the SDK processing-only and stateless
- do not store embeddings or implement app workflows like clock-in / clock-out inside the SDK

## Instructions

- The user initially wanted a Flutter plugin SDK for real-time face recognition and identity verification.
- The user wanted the implementation plan saved and updated as work progressed.
- The repo evolved around an anti-spoof-model-first direction at first.
- Later, the user changed the requirements to a simpler and more reusable SDK design.
- Final agreed direction:
  - processing-only SDK
  - reusable across multiple apps
  - host apps own embedding storage and business logic
  - `enroll()` remains in the SDK
  - Android and iOS should both use Google ML Kit for the gate before embedding extraction

## Discoveries

- A full Flutter plugin scaffold was built in this repo.
- `MobileFaceNet` support exists in the current implementation.
- Android currently already uses Google ML Kit face detection.
- iOS has now been migrated from `Vision` to Google ML Kit face detection to match the final plan.
- The current public models, docs, and example app still contain anti-spoof-specific language and settings.
- The example app is currently more calibration-oriented than the final generic enroll / verify direction.
- The current implementation already has reusable work for:
  - preprocessing
  - enrollment averaging
  - cosine similarity verification
  - camera integration

## Accomplished

Completed so far:

- wrote and saved the implementation plan in `docs/IMPLEMENTATION_PLAN.md`
- built the Flutter plugin scaffold
- implemented Android native detection, preprocessing, embedding, verify, and enroll flows
- implemented iOS native detection, preprocessing, embedding, verify, and enroll flows
- built a live example app with camera integration
- added initial tests for config/model/result parsing and platform delegation
- updated the implementation plan to the final product direction:
  - processing-only SDK
  - ML Kit gate before embedding
  - generic multi-app usage
  - no embedding storage in the SDK
- aligned Dart public models to the new processing-only API
- refactored Android and iOS result contracts to generic face-gate terminology
- migrated iOS native detection from `Vision` to Google ML Kit
- refreshed the example app to generic enroll / verify terminology
- verified `flutter analyze`, `flutter test`, example analyze, `pod install`, and iOS simulator build

## Current In Progress

- docs are aligned and should stay in sync with ongoing implementation work
- legacy anti-spoof native files were removed from the active SDK path
- threshold calibration and broader on-device validation are still pending

## Next Steps

1. Recalibrate and validate behavior on Android and iPhone target devices.
2. Record threshold and performance results for the production-readiness checklist.
3. Record threshold and performance results in the release checklist after on-device validation.

## Relevant Files / Directories

- `docs/IMPLEMENTATION_PLAN.md`
- `docs/README.md`
- `docs/CALIBRATION_CHECKLIST.md`
- `docs/STATUS_MEANINGS.md`
- `docs/WORK_SO_FAR.md`
- `lib/src/models/sdk_config.dart`
- `lib/src/models/face_result.dart`
- `android/src/main/kotlin/com/aif/face_recognition_sdk/FaceRecognitionSdkPlugin.kt`
- `android/src/main/kotlin/com/aif/face_recognition_sdk/FacePreprocessor.kt`
- `ios/Classes/FaceRecognitionSdkPlugin.swift`
- `ios/Classes/FacePreprocessor.swift`
- `example/lib/main.dart`
- `test/sdk_models_test.dart`
- `test/sdk_platform_test.dart`
