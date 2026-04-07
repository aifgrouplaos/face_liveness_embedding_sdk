package com.aif.face_recognition_sdk

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import org.tensorflow.lite.Interpreter
import java.io.File
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.MappedByteBuffer
import java.nio.channels.FileChannel
import kotlin.math.sqrt

internal class MobileFaceNetClassifier(
    private val context: Context,
    private val flutterAssets: FlutterPlugin.FlutterAssets,
) {
    private var interpreter: Interpreter? = null
    private var lastError: String? = null
    private var settings = FaceModelSettings()

    fun configure(configuration: Map<String, Any?>) {
        settings = FaceModelSettings.from(configuration)
        close()

        val modelBuffer = runCatching { loadModelBuffer(settings) }.getOrElse { error ->
            lastError = error.message ?: "Unable to load MobileFaceNet model."
            return
        }

        interpreter = runCatching {
            val options = Interpreter.Options().apply {
                numThreads = 2
            }
            Interpreter(modelBuffer, options)
        }.getOrElse { error ->
            lastError = error.message ?: "Unable to create MobileFaceNet interpreter."
            null
        }
    }

    fun extractEmbedding(input: FloatArray): EmbeddingPrediction {
        val currentInterpreter = interpreter
            ?: return EmbeddingPrediction(
                embedding = emptyList(),
                failureReason = lastError ?: "MobileFaceNet model is not available.",
            )

        val inputShape = currentInterpreter.getInputTensor(0).shape()
        val expectedElements = inputShape.drop(1).fold(1) { acc, dim -> acc * dim }
        if (input.size != expectedElements) {
            return EmbeddingPrediction(
                embedding = emptyList(),
                failureReason = "MobileFaceNet input size ${input.size} does not match expected size $expectedElements.",
            )
        }

        val inputBuffer = ByteBuffer.allocateDirect(input.size * 4).order(ByteOrder.nativeOrder())
        input.forEach { inputBuffer.putFloat(it) }
        inputBuffer.rewind()

        val outputShape = currentInterpreter.getOutputTensor(0).shape()
        val outputElements = outputShape.fold(1) { acc, dim -> acc * dim }
        val outputBuffer = ByteBuffer.allocateDirect(outputElements * 4).order(ByteOrder.nativeOrder())

        return runCatching {
            currentInterpreter.run(inputBuffer, outputBuffer)
            outputBuffer.rewind()
            val rawEmbedding = FloatArray(outputElements)
            outputBuffer.asFloatBuffer().get(rawEmbedding)
            EmbeddingPrediction(
                embedding = l2Normalize(rawEmbedding).map { it.toDouble() },
                failureReason = null,
            )
        }.getOrElse { error ->
            EmbeddingPrediction(
                embedding = emptyList(),
                failureReason = error.message ?: "MobileFaceNet inference failed.",
            )
        }
    }

    fun close() {
        interpreter?.close()
        interpreter = null
    }

    private fun l2Normalize(vector: FloatArray): FloatArray {
        val sumSquares = vector.fold(0.0) { acc, value -> acc + (value * value) }
        val norm = sqrt(sumSquares).toFloat()
        if (norm <= 0f) {
            return vector
        }

        return FloatArray(vector.size) { index -> vector[index] / norm }
    }

    private fun loadModelBuffer(settings: FaceModelSettings): MappedByteBuffer {
        settings.modelPath?.takeIf { it.isNotBlank() }?.let { path ->
            val file = File(path)
            if (file.exists()) {
                return mapFile(file)
            }
        }

        settings.assetName.takeIf { it.isNotBlank() }?.let { assetName ->
            val assetKey = flutterAssets.getAssetFilePathByName(assetName)
            return context.assets.openFd(assetKey).use { descriptor ->
                FileInputStream(descriptor.fileDescriptor).channel.use { channel ->
                    channel.map(
                        FileChannel.MapMode.READ_ONLY,
                        descriptor.startOffset,
                        descriptor.declaredLength,
                    )
                }
            }
        }

        throw IllegalStateException("MobileFaceNet model path or asset name is required.")
    }

    private fun mapFile(file: File): MappedByteBuffer {
        return FileInputStream(file).channel.use { channel ->
            channel.map(FileChannel.MapMode.READ_ONLY, 0, file.length())
        }
    }
}

internal data class EmbeddingPrediction(
    val embedding: List<Double>,
    val failureReason: String?,
)

internal data class FaceModelSettings(
    val assetName: String,
    val modelPath: String?,
) {
    companion object {
        fun from(configuration: Map<String, Any?>): FaceModelSettings {
            return FaceModelSettings(
                assetName = configuration["faceModelAsset"] as? String ?: "model/mobile_face_net.tflite",
                modelPath = configuration["faceModelPath"] as? String,
            )
        }
    }
}
