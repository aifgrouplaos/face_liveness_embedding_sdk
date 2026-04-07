# Calibration Checklist

Use this checklist to prepare the SDK for real-world verification behavior.

## 1. Confirm basic model loading

- verify `model/mobile_face_net.tflite` is packaged correctly
- run the example app on Android and iOS
- confirm embeddings can be produced from clear single-face frames
- confirm embedding length is `192`

## 2. Validate the face gate

Confirm the SDK rejects:

- no-face frames
- multi-face frames
- very small faces
- off-center faces
- excessive pose angles
- blurry frames
- unstable frames

Confirm the SDK accepts:

- clear frontal face frames
- normal indoor lighting conditions
- repeatable frames from the same person

## 3. Tune match threshold

Start with:

- `matchThreshold = 0.58`

Then test with:

- same person across multiple sessions
- different people
- different lighting conditions
- different distances from the camera
- slightly varied head pose

Record the threshold where:

- same-person matches are accepted reliably
- different-person matches are rejected reliably

For attendance-grade use cases, prioritize low false accept rate.

## 4. Validate enrollment stability

- enroll using `3-5` accepted frames
- repeat enrollment for the same person across sessions
- verify that resulting embeddings remain stable enough for matching
- reject enrollment when no accepted frames are available

## 5. Validate verification behavior

- verify same-person acceptance
- verify different-person rejection
- verify retries after invalid or poor-quality frames
- verify score behavior near the chosen threshold

## 6. Measure device behavior

Record on Android and iPhone target devices:

- process latency
- verify latency
- estimated FPS
- rate of `no_face`, `invalid_face`, and `not_real`

Test on:

- low-end Android
- mid-range Android
- iPhone target device

## 7. Record chosen configuration

Document final values for:

- `matchThreshold`
- `minFaceSize`
- `maxYaw`
- `maxPitch`
- `maxRoll`
- `blurThreshold`
- `stableFrameCount`

Recommended place:

- `docs/README.md`
- deployment config file
- release notes for the SDK version

## 8. Final pre-release checks

- Android example builds and runs
- iOS example builds and runs
- embeddings remain length `192`
- enroll and verify flows work consistently
- average latency is acceptable on target devices
- docs clearly state the SDK is processing-only and stateless
