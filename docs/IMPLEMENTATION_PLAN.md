# Face Recognition SDK Implementation Plan

## Goal

Build a production-ready Flutter plugin SDK for Android and iOS that processes face input into face embeddings and verification results.

The SDK is designed as a reusable processing layer for multiple apps.

The SDK must:

- accept camera face frames from host apps
- use Google ML Kit for face detection and real-face gating on Android and iOS
- run `MobileFaceNet` only after the input passes the face gate
- generate a normalized `192`-dimensional face embedding
- compare a live embedding with a caller-provided reference embedding in real time
- provide generic results that host apps can use for check-in, attendance, re-authentication, or other flows

The SDK must not:

- store face embeddings
- store user identity data
- implement business workflows such as clock-in or clock-out
- manage backend sync or user records

---

## Primary Use Model

The SDK is a stateless face-processing engine.

### Host App Responsibilities
- capture frames from camera
- call SDK methods
- store enrolled reference embeddings outside the SDK
- decide what to do with `match` or `no_match`

### SDK Responsibilities
- validate face input
- determine whether the frame is acceptable as a real face for attendance-grade verification
- generate embeddings
- compare live embeddings against provided reference embeddings
- return structured processing results

---

## Inputs And Outputs

### Input
- camera frames
  - Android: `YUV420` / `NV21`
  - iOS: `BGRA` / native pixel buffer
- optional reference embedding provided by host app during verification

### Output
- face processing status
- real-face gate result
- `192`-dimensional embedding when available
- similarity score for verification
- `match` / `no_match`
- failure reason when processing stops early

---

## Production-Ready Target

Production-ready means the SDK is:

- feature-complete for enroll and verify flows
- validated on Android and iOS target devices
- calibrated for matching thresholds using real-world samples
- documented with clear limits and expected behavior
- safe to integrate into multiple host apps as a processing-only component

This does not mean the SDK provides banking-grade spoof resistance.

This version targets practical attendance-grade or check-in-style verification, not high-security identity proofing.

---

## V1 Scope

### Included
- Flutter plugin SDK for Android and iOS
- real-time frame intake from Flutter camera stream
- Google ML Kit face detection on Android and iOS
- face landmarks and pose extraction
- face quality validation
- practical real-face gate using ML Kit-derived signals
- native preprocessing pipeline
- `MobileFaceNet` embedding inference
- cosine-similarity face verification
- enrollment from multiple accepted frames
- generic result objects for process, enroll, and verify
- example Flutter app for generic enroll and verify flows

### Excluded From V1
- embedding or identity storage
- clock-in / clock-out workflow logic
- user management
- backend synchronization
- banking-grade / KYC-grade liveness guarantees
- active challenge-response flow
- depth / IR camera support
- server-side verification
- multi-face identification
- advanced spoof analytics dashboard

---

## Chosen Stack

### Face Detection And Gate
- Android: Google ML Kit Face Detection
- iOS: Google ML Kit Face Detection

Purpose:
- detect a single face
- extract landmarks and pose data
- enforce face quality and real-face gate rules before embedding extraction

### Recognition Model
- `MobileFaceNet`
- source file: `model/mobile_face_net.tflite`

Purpose:
- generate `192`-dimensional embeddings for person comparison

### Runtime Engine
- TensorFlow Lite
- CPU-first implementation
- optional delegates later:
  - Android: XNNPACK / NNAPI
  - iOS: Core ML delegate

---

## Architecture

### Flutter Layer
Responsible for:

- public SDK API
- camera stream integration
- configuration objects
- result models
- example app integration

### Native Android Layer
Responsible for:

- `YUV_420_888` / `NV21` conversion
- ML Kit face detector bridge
- face validation and real-face gate evaluation
- crop / align / resize pipeline
- `MobileFaceNet` inference

### Native iOS Layer
Responsible for:

- `CVPixelBuffer` / `BGRA` conversion
- ML Kit face detector bridge
- face validation and real-face gate evaluation
- crop / align / resize pipeline
- `MobileFaceNet` inference

---

## Face Gate Design

The SDK must reject frames when:

- no face is detected
- more than one face is detected
- face is too small
- face is not centered enough
- face pose exceeds thresholds
- landmarks are missing or unreliable
- image is too blurry
- frame is not stable enough for attendance-grade verification

The gate is based on ML Kit-derived face signals and quality checks.

This gate is intended to block bad or low-confidence frames before embedding extraction.

If the frame passes the gate:

- preprocess the face crop natively
- run `MobileFaceNet`
- normalize the output embedding

If the frame does not pass the gate:

- do not run embedding extraction
- return a structured failure result

---

## Core Flows

### Process Flow
1. Capture camera frame
2. Detect one face with ML Kit
3. Validate size, center, pose, landmarks, blur, and stability
4. Apply real-face gate
5. If accepted, crop and preprocess the face
6. Run `MobileFaceNet`
7. L2 normalize the output embedding
8. Return processing result

### Enrollment Flow
1. Host app provides multiple frames
2. SDK applies the normal face gate to each frame
3. SDK runs `MobileFaceNet` on accepted frames only
4. SDK averages accepted embeddings
5. SDK L2 normalizes the final embedding
6. SDK returns the final reference embedding to the host app

### Verification Flow
1. Host app provides one live frame and one reference embedding
2. SDK processes the live frame
3. If the frame passes, SDK generates the live embedding
4. SDK computes cosine similarity against the provided reference embedding
5. SDK returns `match` or `no_match` with score and status

---

## SDK API Direction

```dart
class FaceRecognitionSdk {
  Future<void> initialize(FaceSdkConfig config);
  Future<FaceProcessResult> processFrame(CameraImage frame);
  Future<FaceEnrollmentResult> enroll(List<CameraImage> frames);
  Future<FaceVerificationResult> verify(
    CameraImage frame,
    List<double> referenceEmbedding,
  );
  Future<void> dispose();
}
```

### Config Object Direction

```dart
class FaceSdkConfig {
  final double matchThreshold;
  final String faceModelAsset;
  final String? faceModelPath;
  final int minFaceSize;
  final int stableFrameCount;
  final int inferenceIntervalMs;
  final double maxYaw;
  final double maxPitch;
  final double maxRoll;
  final double blurThreshold;
}
```

### Result Object Direction

```dart
class FaceVerificationResult {
  final String status;
  final String? failureReason;
  final List<double> embedding;
  final double score;
  final bool isMatch;
  final bool isReal;
}
```

Notes:

- `enroll()` stays in the SDK as a processing convenience method
- the SDK returns embeddings but does not persist them
- host apps own embedding storage and business decisions

---

## Status Model

Planned primary status values:

- `waiting`
- `no_face`
- `multiple_faces`
- `invalid_face`
- `not_real`
- `ready_for_embedding`
- `verified`
- `no_match`
- `detector_error`
- `model_error`

Status wording must remain generic so the SDK can be used across multiple apps.

---

## Current Implementation Status

### Current Summary
- [x] Flutter plugin scaffold created
- [x] Android pipeline exists for detection, preprocessing, embedding, verification, and enrollment
- [x] iOS pipeline exists for detection, preprocessing, embedding, verification, and enrollment
- [x] Flutter example app wired to a live camera stream
- [x] Public API and docs aligned to the new processing-only SDK direction
- [x] Android gate logic simplified around ML Kit-derived rules
- [x] iOS migrated from `Vision` to Google ML Kit for detector parity
- [x] Example app refreshed to generic enroll / verify terminology
- [x] Legacy anti-spoof native files removed from the active SDK path
- [ ] Threshold calibration and broader on-device validation are still pending

### Reusable Existing Work
- Flutter plugin structure
- `MobileFaceNet` integration
- native preprocessing pipeline
- cosine similarity verification
- enrollment averaging flow
- camera-based example app

### Work To Retire Or Refactor
- anti-spoof-model-first requirements and docs
- anti-spoof-specific config surface
- anti-spoof-specific result naming
- iOS `Vision` detector implementation
- example calibration UI tied to anti-spoof model indexes

---

## Implementation Phases

### Phase 1: Requirements And Docs Reset `[completed]`
- [x] rewrite docs around processing-only SDK scope
- [x] define ML Kit gate -> embedding -> compare flow
- [x] state clearly that embeddings are not stored by the SDK
- [x] keep attendance/check-in only as example integrations

### Phase 2: Public API Reset `[completed]`
- [x] simplify `FaceSdkConfig` to generic processing settings
- [x] remove anti-spoof-specific public fields
- [x] update result models to generic gate and verification terminology
- [x] keep `enroll()` as a first-class SDK method

### Phase 3: Android Alignment `[completed]`
- [x] keep ML Kit face detection
- [x] replace anti-spoof gating with ML Kit-derived real-face gate rules
- [x] run embedding extraction only after the gate passes
- [x] preserve enroll and verify behavior with the new status contract

### Phase 4: iOS Detector Migration `[completed]`
- [x] replace `Vision` face detection with Google ML Kit face detection
- [x] align iOS gate behavior with Android
- [x] preserve preprocessing and embedding extraction where possible
- [x] validate parity of statuses and outputs

### Phase 5: Example App Refresh `[completed]`
- [x] update UI language to generic enroll / verify terms
- [x] remove anti-spoof tuning controls
- [x] keep face overlay, guidance, and benchmark metrics
- [x] demonstrate generic multi-app integration behavior

### Phase 6: Testing And Calibration `[in progress]`
- [x] update unit tests for new config and result contracts
- [ ] validate same-person vs different-person thresholds
- [ ] test rejection of poor-quality frames on Android and iOS
- [ ] benchmark latency and FPS on target devices

### Phase 7: Native Cleanup `[pending]`
- [x] remove or archive unused anti-spoof native files and assets
- [x] simplify preprocessing structures that still carry anti-spoof-only fields
- [x] verify iOS CocoaPods setup remains stable after ML Kit migration

---

## Production Readiness Requirements

Before calling the SDK production-ready, all of the following must be true:

- Android and iOS both use Google ML Kit for detection and face gating
- embedding extraction works reliably after successful face gating
- `enroll()` returns stable normalized embeddings from multiple accepted frames
- `verify()` returns consistent similarity scores and match decisions
- threshold tuning is completed with real same-person and different-person samples
- docs clearly state that the SDK is processing-only and stateless
- example app demonstrates the generic integration pattern cleanly
- automated tests cover SDK config, result parsing, enroll, and verify contracts
- on-device validation is recorded for Android and iPhone target devices

---

## Calibration Plan

### Match Threshold Calibration
Collect verification samples for:

- same person across sessions
- different people
- varying lighting conditions
- varying pose and distance conditions

Tune threshold to balance:

- false accept rate
- false reject rate

For attendance-grade usage, prioritize preventing wrong-person matches.

### Face Gate Validation
Validate that the gate rejects:

- no-face frames
- multi-face frames
- very small faces
- off-center faces
- excessive pose angles
- blurred frames
- unstable frames

Validate that the gate accepts:

- clear single-face frontal input
- normal indoor lighting conditions
- repeatable enrollment and verification frames

---

## Risks And Mitigations

### Risk: False Matches
Mitigation:
- calibrate `matchThreshold` using same-person and different-person data
- prioritize low false accept rate
- validate across real device capture conditions

### Risk: False Rejects For Valid Users
Mitigation:
- average embeddings across multiple enrollment frames
- tune face gate thresholds on target devices
- support retry on low-quality frames

### Risk: iOS And Android Diverge
Mitigation:
- standardize on Google ML Kit for both platforms
- align validation rules and status wording
- compare outputs using shared sample scenarios

### Risk: SDK Scope Creep
Mitigation:
- keep storage and business logic outside the SDK
- keep the public API focused on processing, enroll, and verify only

### Risk: Misuse As High-Security Liveness Product
Mitigation:
- document the attendance-grade target clearly
- do not claim banking-grade spoof resistance
- position stronger spoof protection as future work if needed

---

## Future Work

Possible future additions after this production-ready baseline:

- direct `compareEmbeddings()` API
- stronger liveness / anti-spoof mode
- challenge-response flow
- optional server-assisted verification
- device-specific threshold presets
- richer benchmarking and telemetry

---

## Success Criteria

- process face frames in real time on Android and iOS
- reject unusable frames before embedding extraction
- generate stable `192`-dimensional embeddings
- support multi-frame enrollment without storing embeddings internally
- compare live embeddings against caller-provided reference embeddings
- return clear generic statuses and failure reasons
- remain reusable across multiple apps without business-logic coupling
