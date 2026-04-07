# Status Meanings

This file explains the generic status values intended for the SDK and example app after the processing-only redesign.

## Processing Status

### `waiting`
- No processed frame has been returned yet.

### `no_face`
- No face was detected in the current frame.
- Action: bring one face into view.

### `multiple_faces`
- More than one face was detected.
- Action: keep only one person in frame.

### `invalid_face`
- A face was detected, but the frame failed validation before embedding extraction.
- Common reasons:
  - face too small
  - face not centered
  - pose too far from frontal
  - landmarks not visible enough
  - frame too blurry
  - frame not stable enough
  - preprocessing failed

### `not_real`
- A face was detected, but the frame did not pass the practical real-face gate.
- Action: retry with a clear, centered, stable live face.

### `ready_for_embedding`
- The frame passed detection, validation, and face gate checks.
- The SDK can generate an embedding from this frame.

### `detector_error`
- Native face detection failed unexpectedly.
- Action: retry and inspect device logs if it repeats.

### `model_error`
- Embedding inference failed unexpectedly.
- Action: inspect logs and verify model compatibility.

## Verification Status

### `verified`
- Verification executed successfully.
- Inspect `isMatch` and `score` to interpret the result.

### `no_match`
- The frame was processed, but the similarity score did not pass the configured match threshold.
- Meaning: the current face does not match the provided reference embedding.

### `match`
- The similarity score passed the configured match threshold.
- Meaning: the current face matches the provided reference embedding.

### `not_run`
- Verification did not execute.
- Common reasons:
  - no valid face input
  - no usable embedding
  - reference embedding missing

## Embedding

### `0`
- No face embedding was produced.
- Usually happens when detection, validation, or face gating fails first.

### `192`
- Expected `MobileFaceNet` embedding size.
- This is the normal successful output length.

## Enrollment

### `enrolled`
- Enrollment succeeded.
- The SDK returned a normalized reference embedding built from accepted frames.

### `enrollment_failed`
- Enrollment did not gather any acceptable frames.
- Action: retry with clearer, more stable frames.

## Important Scope Note

The SDK only processes data and returns results.

The SDK does not:

- store embeddings
- store users
- decide business outcomes such as clock-in or clock-out

The host app decides what to do with `match`, `no_match`, `verified`, or `enrolled`.
