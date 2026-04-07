package com.aif.face_recognition_sdk

import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.Face
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetector
import com.google.mlkit.vision.face.FaceDetectorOptions
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlin.math.abs

class FaceRecognitionSdkPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private var configuration: Map<String, Any?> = emptyMap()
    private lateinit var faceDetector: FaceDetector
    private val facePreprocessor = FacePreprocessor()
    private lateinit var mobileFaceNetClassifier: MobileFaceNetClassifier

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        mobileFaceNetClassifier = MobileFaceNetClassifier(binding.applicationContext, binding.flutterAssets)
        faceDetector = FaceDetection.getClient(
            FaceDetectorOptions.Builder()
                .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
                .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_ALL)
                .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_NONE)
                .enableTracking()
                .build(),
        )
        channel = MethodChannel(binding.binaryMessenger, "face_recognition_sdk")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "initialize" -> {
                @Suppress("UNCHECKED_CAST")
                configuration = call.arguments as? Map<String, Any?> ?: emptyMap()
                mobileFaceNetClassifier.configure(configuration)
                result.success(null)
            }

            "processFrame" -> handleProcessFrame(call, result)

            "enroll" -> handleEnroll(call, result)

            "verify" -> handleVerify(call, result)

            "dispose" -> {
                configuration = emptyMap()
                mobileFaceNetClassifier.close()
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        mobileFaceNetClassifier.close()
        faceDetector.close()
    }

    private fun handleProcessFrame(call: MethodCall, result: Result) {
        @Suppress("UNCHECKED_CAST")
        val frame = call.arguments as? Map<String, Any?>
        if (frame == null) {
            result.success(defaultProcessResult(status = "invalid_argument", failureReason = "Frame payload is missing."))
            return
        }

        val parsedFrame = try {
            parseFrame(frame)
        } catch (e: IllegalArgumentException) {
            result.success(defaultProcessResult(status = "invalid_argument", failureReason = e.message))
            return
        } catch (e: UnsupportedOperationException) {
            result.success(defaultProcessResult(status = "unsupported_format", failureReason = e.message))
            return
        }

        analyzeFrame(parsedFrame)
            .addOnSuccessListener { pipeline ->
                result.success(pipeline.toProcessMap())
            }
            .addOnFailureListener { error ->
                result.success(
                    defaultProcessResult(
                        status = "detector_error",
                        failureReason = error.message ?: "Face detection failed.",
                    ),
                )
            }
    }

    private fun handleVerify(call: MethodCall, result: Result) {
        @Suppress("UNCHECKED_CAST")
        val arguments = call.arguments as? Map<String, Any?>
        val frameMap = arguments?.get("frame") as? Map<String, Any?>
        val referenceEmbedding = (arguments?.get("referenceEmbedding") as? List<*>)
            ?.mapNotNull { (it as? Number)?.toDouble() }
            ?: emptyList()

        if (frameMap == null) {
            result.success(defaultVerificationResult(failureReason = "Frame payload is missing."))
            return
        }

        if (referenceEmbedding.isEmpty()) {
            result.success(defaultVerificationResult(failureReason = "Reference embedding is missing."))
            return
        }

        val parsedFrame = try {
            parseFrame(frameMap)
        } catch (e: IllegalArgumentException) {
            result.success(defaultVerificationResult(status = "invalid_argument", failureReason = e.message ?: "Invalid frame payload."))
            return
        } catch (e: UnsupportedOperationException) {
            result.success(defaultVerificationResult(status = "unsupported_format", failureReason = e.message ?: "Unsupported frame format."))
            return
        }

        analyzeFrame(parsedFrame)
            .addOnSuccessListener { pipeline ->
                result.success(pipeline.toVerificationMap(referenceEmbedding, configDouble("matchThreshold", 0.58)))
            }
            .addOnFailureListener { error ->
                result.success(
                    defaultVerificationResult(
                        status = "detector_error",
                        failureReason = error.message ?: "Face detection failed.",
                    ),
                )
            }
    }

    private fun handleEnroll(call: MethodCall, result: Result) {
        @Suppress("UNCHECKED_CAST")
        val arguments = call.arguments as? Map<String, Any?>
        val frameMaps = arguments?.get("frames") as? List<Map<String, Any?>>

        if (frameMaps.isNullOrEmpty()) {
            result.success(defaultEnrollmentResult(failureReason = "Enrollment frames are missing."))
            return
        }

        val parsedFrames = try {
            frameMaps.map { parseFrame(it) }
        } catch (e: IllegalArgumentException) {
            result.success(defaultEnrollmentResult(status = "invalid_argument", failureReason = e.message ?: "Invalid enrollment frame."))
            return
        } catch (e: UnsupportedOperationException) {
            result.success(defaultEnrollmentResult(status = "unsupported_format", failureReason = e.message ?: "Unsupported enrollment frame format."))
            return
        }

        val tasks = parsedFrames.map { analyzeFrame(it) }
        Tasks.whenAllSuccess<FramePipelineResult>(tasks)
            .addOnSuccessListener { pipelines ->
                val accepted = pipelines.filter { it.failureReason == null && it.embedding.isNotEmpty() }
                if (accepted.isEmpty()) {
                    val failureReason = pipelines.firstNotNullOfOrNull { it.failureReason }
                        ?: "No valid live face frames were accepted for enrollment."
                    result.success(
                        defaultEnrollmentResult(
                            status = "enrollment_failed",
                            failureReason = failureReason,
                        ),
                    )
                    return@addOnSuccessListener
                }

                val averagedEmbedding = averageEmbeddings(accepted.map { it.embedding })
                result.success(
                    mapOf(
                        "status" to "enrolled",
                        "failureReason" to null,
                        "acceptedFrames" to accepted.size,
                        "embedding" to averagedEmbedding,
                    ),
                )
            }
            .addOnFailureListener { error ->
                result.success(
                    defaultEnrollmentResult(
                        status = "detector_error",
                        failureReason = error.message ?: "Enrollment processing failed.",
                    ),
                )
            }
    }

    private fun analyzeFrame(parsedFrame: ParsedFrame) =
        faceDetector.process(parsedFrame.inputImage)
            .continueWith { task ->
                if (!task.isSuccessful) {
                    throw task.exception ?: IllegalStateException("Face detection failed.")
                }
                buildFramePipelineResult(parsedFrame, task.result ?: emptyList())
            }

    private fun parseFrame(frame: Map<String, Any?>): ParsedFrame {
        val width = (frame["width"] as? Number)?.toInt()
            ?: throw IllegalArgumentException("Frame width is required.")
        val height = (frame["height"] as? Number)?.toInt()
            ?: throw IllegalArgumentException("Frame height is required.")
        val rotationDegrees = (frame["rotationDegrees"] as? Number)?.toInt()
            ?: throw IllegalArgumentException("Frame rotationDegrees is required.")
        val format = frame["format"] as? String
            ?: throw IllegalArgumentException("Frame format is required.")

        return when (format) {
            "yuv420" -> {
                val nv21 = yuv420ToNv21(frame, width, height)
                ParsedFrame(
                    width = width,
                    height = height,
                    rotationDegrees = rotationDegrees,
                    nv21Bytes = nv21,
                    inputImage = InputImage.fromByteArray(
                        nv21,
                        width,
                        height,
                        rotationDegrees,
                        InputImage.IMAGE_FORMAT_NV21,
                    ),
                )
            }
            "nv21" -> {
                val planes = framePlanes(frame)
                val bytes = planes.firstOrNull()?.bytes
                    ?: throw IllegalArgumentException("NV21 frame bytes are missing.")
                ParsedFrame(
                    width = width,
                    height = height,
                    rotationDegrees = rotationDegrees,
                    nv21Bytes = bytes,
                    inputImage = InputImage.fromByteArray(
                        bytes,
                        width,
                        height,
                        rotationDegrees,
                        InputImage.IMAGE_FORMAT_NV21,
                    ),
                )
            }
            else -> throw UnsupportedOperationException("Android processFrame currently supports yuv420 and nv21 only.")
        }
    }

    private fun buildFramePipelineResult(frame: ParsedFrame, faces: List<Face>): FramePipelineResult {
        val width = frame.width.toDouble()
        val height = frame.height.toDouble()

        if (faces.isEmpty()) {
            return FramePipelineResult(status = "no_face", failureReason = "No face detected.")
        }

        if (faces.size > 1) {
            return FramePipelineResult(
                status = "multiple_faces",
                failureReason = "Multiple faces detected. Please keep only one face in frame.",
                quality = mapOf(
                    "hasSingleFace" to false,
                    "isCentered" to false,
                    "poseValid" to false,
                    "isStable" to false,
                    "isBlurred" to false,
                ),
            )
        }

        val face = faces.first()
        val box = face.boundingBox
        val centerX = (box.left + box.right) / 2.0
        val centerY = (box.top + box.bottom) / 2.0
        val centered = width > 0 && height > 0 &&
            abs(centerX - (width / 2.0)) <= width * 0.2 &&
            abs(centerY - (height / 2.0)) <= height * 0.2
        val minFaceSize = configInt("minFaceSize", 160)
        val sizeValid = box.width() >= minFaceSize && box.height() >= minFaceSize
        val poseValid =
            abs(face.headEulerAngleY) <= configDouble("maxYaw", 15.0) &&
                abs(face.headEulerAngleX) <= configDouble("maxPitch", 15.0) &&
                abs(face.headEulerAngleZ) <= configDouble("maxRoll", 15.0)
        val landmarks = buildLandmarks(face)
        val hasRequiredLandmarks = landmarks.isNotEmpty()
        val preprocessing = if (sizeValid && centered && poseValid && hasRequiredLandmarks) {
            runCatching {
                facePreprocessor.preprocess(
                    nv21 = frame.nv21Bytes,
                    width = frame.width,
                    height = frame.height,
                    rotationDegrees = frame.rotationDegrees,
                    face = face,
                )
            }.getOrNull()
        } else {
            null
        }
        val blurScore = preprocessing?.blurScore ?: 0.0
        val isBlurred = preprocessing != null && blurScore < configDouble("blurThreshold", 90.0)
        val embeddingPrediction = if (
            preprocessing != null &&
            !isBlurred
        ) {
            mobileFaceNetClassifier.extractEmbedding(preprocessing.embeddingInput)
        } else {
            EmbeddingPrediction(emptyList(), null)
        }
        val quality = mapOf(
            "hasSingleFace" to true,
            "isCentered" to centered,
            "poseValid" to poseValid,
            "isStable" to true,
            "isBlurred" to isBlurred,
        )
        val failureReason = when {
            !sizeValid -> "Face is too small. Move closer to the camera."
            !centered -> "Face is not centered in frame."
            !poseValid -> "Face pose is outside the allowed range."
            !hasRequiredLandmarks -> "Face landmarks are not sufficiently visible."
            preprocessing == null -> "Face preprocessing failed."
            isBlurred -> "Face image is too blurry. Hold the camera steady."
            embeddingPrediction.failureReason != null -> embeddingPrediction.failureReason
            else -> null
        }
        val faceGateStatus = when {
            preprocessing == null || isBlurred -> "not_real"
            failureReason == null -> "passed"
            else -> "not_real"
        }

        return FramePipelineResult(
            status = if (failureReason == null) "ready_for_embedding" else if (preprocessing != null && !isBlurred) "not_real" else "invalid_face",
            failureReason = failureReason,
            embedding = embeddingPrediction.embedding,
            boundingBox = mapOf(
                "left" to box.left.toDouble(),
                "top" to box.top.toDouble(),
                "right" to box.right.toDouble(),
                "bottom" to box.bottom.toDouble(),
            ),
            landmarks = landmarks,
            quality = quality,
            faceGate = mapOf(
                "isReal" to (failureReason == null),
                "status" to faceGateStatus,
            ),
            preprocessing = mapOf(
                "cropWidth" to (preprocessing?.cropWidth ?: 0),
                "cropHeight" to (preprocessing?.cropHeight ?: 0),
                "embeddingInputSize" to (preprocessing?.embeddingInput?.size ?: 0),
                "blurScore" to blurScore,
            ),
        )
    }

    private fun buildLandmarks(face: Face): List<Map<String, Any?>> {
        val landmarkTypes = listOf(
            FaceLandmarkSpec("leftEye", Face.LANDMARK_LEFT_EYE),
            FaceLandmarkSpec("rightEye", Face.LANDMARK_RIGHT_EYE),
            FaceLandmarkSpec("noseBase", Face.LANDMARK_NOSE_BASE),
            FaceLandmarkSpec("leftCheek", Face.LANDMARK_LEFT_CHEEK),
            FaceLandmarkSpec("rightCheek", Face.LANDMARK_RIGHT_CHEEK),
            FaceLandmarkSpec("leftEar", Face.LANDMARK_LEFT_EAR),
            FaceLandmarkSpec("rightEar", Face.LANDMARK_RIGHT_EAR),
            FaceLandmarkSpec("leftMouth", Face.LANDMARK_LEFT_MOUTH),
            FaceLandmarkSpec("rightMouth", Face.LANDMARK_RIGHT_MOUTH),
            FaceLandmarkSpec("bottomMouth", Face.LANDMARK_BOTTOM_MOUTH),
        )

        return landmarkTypes.mapNotNull { spec ->
            val point = face.getLandmark(spec.type)?.position ?: return@mapNotNull null
            mapOf(
                "type" to spec.name,
                "x" to point.x.toDouble(),
                "y" to point.y.toDouble(),
            )
        }
    }

    private fun yuv420ToNv21(frame: Map<String, Any?>, width: Int, height: Int): ByteArray {
        val planes = framePlanes(frame)
        if (planes.size < 3) {
            throw IllegalArgumentException("YUV420 frame must contain 3 planes.")
        }

        val yPlane = planes[0]
        val uPlane = planes[1]
        val vPlane = planes[2]
        val ySize = width * height
        val nv21 = ByteArray(ySize + (width * height / 2))

        copyPlane(
            source = yPlane.bytes,
            sourceRowStride = yPlane.bytesPerRow,
            sourcePixelStride = yPlane.bytesPerPixel ?: 1,
            width = width,
            height = height,
            target = nv21,
            targetOffset = 0,
            targetPixelStride = 1,
        )

        val chromaHeight = height / 2
        val chromaWidth = width / 2
        var outputOffset = ySize
        for (row in 0 until chromaHeight) {
            val uRowOffset = row * uPlane.bytesPerRow
            val vRowOffset = row * vPlane.bytesPerRow
            for (col in 0 until chromaWidth) {
                val uIndex = uRowOffset + (col * (uPlane.bytesPerPixel ?: 1))
                val vIndex = vRowOffset + (col * (vPlane.bytesPerPixel ?: 1))
                nv21[outputOffset++] = vPlane.bytes[vIndex]
                nv21[outputOffset++] = uPlane.bytes[uIndex]
            }
        }

        return nv21
    }

    private fun copyPlane(
        source: ByteArray,
        sourceRowStride: Int,
        sourcePixelStride: Int,
        width: Int,
        height: Int,
        target: ByteArray,
        targetOffset: Int,
        targetPixelStride: Int,
    ) {
        var outputOffset = targetOffset
        for (row in 0 until height) {
            val rowOffset = row * sourceRowStride
            for (col in 0 until width) {
                target[outputOffset] = source[rowOffset + (col * sourcePixelStride)]
                outputOffset += targetPixelStride
            }
        }
    }

    private fun framePlanes(frame: Map<String, Any?>): List<FramePlane> {
        @Suppress("UNCHECKED_CAST")
        val planeMaps = frame["planes"] as? List<Map<String, Any?>>
            ?: throw IllegalArgumentException("Frame planes are required.")

        return planeMaps.map { plane ->
            FramePlane(
                bytes = plane["bytes"] as? ByteArray
                    ?: throw IllegalArgumentException("Frame plane bytes are missing."),
                bytesPerRow = (plane["bytesPerRow"] as? Number)?.toInt()
                    ?: throw IllegalArgumentException("Frame plane bytesPerRow is required."),
                bytesPerPixel = (plane["bytesPerPixel"] as? Number)?.toInt(),
            )
        }
    }

    private fun configDouble(key: String, defaultValue: Double): Double {
        return (configuration[key] as? Number)?.toDouble() ?: defaultValue
    }

    private fun configInt(key: String, defaultValue: Int): Int {
        return (configuration[key] as? Number)?.toInt() ?: defaultValue
    }

    private fun averageEmbeddings(embeddings: List<List<Double>>): List<Double> {
        if (embeddings.isEmpty()) {
            return emptyList()
        }

        val size = embeddings.first().size
        if (size == 0 || embeddings.any { it.size != size }) {
            return emptyList()
        }

        val averaged = DoubleArray(size)
        for (embedding in embeddings) {
            for (index in 0 until size) {
                averaged[index] += embedding[index]
            }
        }

        for (index in averaged.indices) {
            averaged[index] /= embeddings.size.toDouble()
        }

        val norm = kotlin.math.sqrt(averaged.sumOf { it * it })
        if (norm <= 0.0) {
            return averaged.toList()
        }

        return averaged.map { it / norm }
    }

    private fun defaultProcessResult(
        status: String = "not_ready",
        failureReason: String = "Native frame processing is not implemented yet.",
        quality: Map<String, Any?> = mapOf(
            "hasSingleFace" to false,
            "isCentered" to false,
            "poseValid" to false,
            "isStable" to false,
            "isBlurred" to false,
        ),
    ): Map<String, Any?> {
        return mapOf(
            "status" to status,
            "failureReason" to failureReason,
            "embedding" to emptyList<Double>(),
            "boundingBox" to null,
            "landmarks" to emptyList<Map<String, Any?>>(),
            "quality" to quality,
            "faceGate" to mapOf(
                "isReal" to false,
                "status" to "unknown",
            ),
        )
    }

    private fun defaultVerificationResult(
        status: String = "not_ready",
        failureReason: String = "Native verification pipeline is not implemented yet.",
    ): Map<String, Any?> {
        return mapOf(
            "status" to status,
            "failureReason" to failureReason,
            "embedding" to emptyList<Double>(),
            "score" to 0.0,
            "isMatch" to false,
            "isReal" to false,
            "faceGateStatus" to "unknown",
        )
    }

    private fun defaultEnrollmentResult(
        status: String = "not_ready",
        failureReason: String = "Native enrollment pipeline is not implemented yet.",
    ): Map<String, Any?> {
        return mapOf(
            "status" to status,
            "failureReason" to failureReason,
            "acceptedFrames" to 0,
            "embedding" to emptyList<Double>(),
        )
    }

    private data class FramePlane(
        val bytes: ByteArray,
        val bytesPerRow: Int,
        val bytesPerPixel: Int?,
    )

    private data class ParsedFrame(
        val width: Int,
        val height: Int,
        val rotationDegrees: Int,
        val nv21Bytes: ByteArray,
        val inputImage: InputImage,
    )

    private data class FaceLandmarkSpec(
        val name: String,
        val type: Int,
    )

    private data class FramePipelineResult(
        val status: String,
        val failureReason: String?,
        val embedding: List<Double> = emptyList(),
        val boundingBox: Map<String, Any?>? = null,
        val landmarks: List<Map<String, Any?>> = emptyList(),
        val quality: Map<String, Any?> = mapOf(
            "hasSingleFace" to false,
            "isCentered" to false,
            "poseValid" to false,
            "isStable" to false,
            "isBlurred" to false,
        ),
        val faceGate: Map<String, Any?> = mapOf(
            "isReal" to false,
            "status" to "unknown",
        ),
        val preprocessing: Map<String, Any?> = emptyMap(),
    ) {
        fun toProcessMap(): Map<String, Any?> {
            return mapOf(
                "status" to status,
                "failureReason" to failureReason,
                "embedding" to embedding,
                "boundingBox" to boundingBox,
                "landmarks" to landmarks,
                "quality" to quality,
                "preprocessing" to preprocessing,
                "faceGate" to faceGate,
            )
        }

        fun toVerificationMap(referenceEmbedding: List<Double>, threshold: Double): Map<String, Any?> {
            if (failureReason != null || embedding.isEmpty()) {
                return mapOf(
                    "status" to status,
                    "failureReason" to failureReason ?: "Embedding is unavailable.",
                    "embedding" to embedding,
                    "score" to 0.0,
                    "isMatch" to false,
                    "isReal" to (faceGate["isReal"] as? Boolean ?: false),
                    "faceGateStatus" to (faceGate["status"] as? String ?: "unknown"),
                )
            }

            val score = cosineSimilarity(embedding, referenceEmbedding)
            return mapOf(
                "status" to if (score >= threshold) "verified" else "no_match",
                "failureReason" to null,
                "embedding" to embedding,
                "score" to score,
                "isMatch" to (score >= threshold),
                "isReal" to (faceGate["isReal"] as? Boolean ?: false),
                "faceGateStatus" to (faceGate["status"] as? String ?: "unknown"),
            )
        }

        private fun cosineSimilarity(a: List<Double>, b: List<Double>): Double {
            if (a.isEmpty() || b.isEmpty() || a.size != b.size) {
                return 0.0
            }

            var dot = 0.0
            var normA = 0.0
            var normB = 0.0
            for (i in a.indices) {
                dot += a[i] * b[i]
                normA += a[i] * a[i]
                normB += b[i] * b[i]
            }

            if (normA <= 0.0 || normB <= 0.0) {
                return 0.0
            }

            return dot / (kotlin.math.sqrt(normA) * kotlin.math.sqrt(normB))
        }
    }
}
