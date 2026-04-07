package com.aif.face_recognition_sdk

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.YuvImage
import com.google.mlkit.vision.face.Face
import java.io.ByteArrayOutputStream
import kotlin.math.atan2
import kotlin.math.max

internal class FacePreprocessor {
    fun preprocess(
        nv21: ByteArray,
        width: Int,
        height: Int,
        rotationDegrees: Int,
        face: Face,
        embeddingSize: Int = 112,
    ): PreprocessedFace {
        val uprightBitmap = nv21ToBitmap(nv21, width, height).rotate(rotationDegrees)
        val faceCrop = cropFace(uprightBitmap, face.boundingBox)
        val alignedFace = alignCroppedFace(faceCrop, face)
        val embeddingBitmap = Bitmap.createScaledBitmap(alignedFace, embeddingSize, embeddingSize, true)

        return PreprocessedFace(
            embeddingInput = bitmapToNormalizedFloatList(embeddingBitmap, normalizeToSignedUnit = true),
            blurScore = computeBlurScore(embeddingBitmap),
            cropWidth = alignedFace.width,
            cropHeight = alignedFace.height,
        )
    }

    private fun nv21ToBitmap(nv21: ByteArray, width: Int, height: Int): Bitmap {
        val yuvImage = YuvImage(nv21, android.graphics.ImageFormat.NV21, width, height, null)
        val outputStream = ByteArrayOutputStream()
        yuvImage.compressToJpeg(Rect(0, 0, width, height), 95, outputStream)
        val jpegBytes = outputStream.toByteArray()
        return BitmapFactory.decodeByteArray(jpegBytes, 0, jpegBytes.size)
            ?: throw IllegalStateException("Unable to decode camera frame.")
    }

    private fun Bitmap.rotate(rotationDegrees: Int): Bitmap {
        if (rotationDegrees % 360 == 0) {
            return this
        }

        val matrix = Matrix().apply {
            postRotate(rotationDegrees.toFloat())
        }
        return Bitmap.createBitmap(this, 0, 0, width, height, matrix, true)
    }

    private fun alignCroppedFace(bitmap: Bitmap, face: Face): Bitmap {
        val leftEye = face.getLandmark(Face.LANDMARK_LEFT_EYE)?.position ?: return bitmap
        val rightEye = face.getLandmark(Face.LANDMARK_RIGHT_EYE)?.position ?: return bitmap
        val cropLeft = face.boundingBox.left.toFloat()
        val cropTop = face.boundingBox.top.toFloat()
        val localLeftEyeX = leftEye.x - cropLeft
        val localLeftEyeY = leftEye.y - cropTop
        val localRightEyeX = rightEye.x - cropLeft
        val localRightEyeY = rightEye.y - cropTop
        val angleRadians = atan2(
            (localRightEyeY - localLeftEyeY).toDouble(),
            (localRightEyeX - localLeftEyeX).toDouble(),
        )
        val angleDegrees = Math.toDegrees(angleRadians).toFloat()
        if (angleDegrees == 0f) {
            return bitmap
        }

        val matrix = Matrix().apply {
            postRotate(-angleDegrees, bitmap.width / 2f, bitmap.height / 2f)
        }
        return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
    }

    private fun cropFace(bitmap: Bitmap, boundingBox: Rect): Bitmap {
        val box = RectF(boundingBox)
        val faceWidth = box.width()
        val faceHeight = box.height()
        val cropSize = max(faceWidth, faceHeight) * 1.35f
        val centerX = box.centerX()
        val centerY = box.centerY() - (faceHeight * 0.08f)

        val left = (centerX - cropSize / 2f).coerceAtLeast(0f)
        val top = (centerY - cropSize / 2f).coerceAtLeast(0f)
        val right = (centerX + cropSize / 2f).coerceAtMost(bitmap.width.toFloat())
        val bottom = (centerY + cropSize / 2f).coerceAtMost(bitmap.height.toFloat())

        val cropRect = Rect(
            left.toInt(),
            top.toInt(),
            max(left.toInt() + 1, right.toInt()),
            max(top.toInt() + 1, bottom.toInt()),
        )

        val safeRect = Rect(
            cropRect.left.coerceIn(0, bitmap.width - 1),
            cropRect.top.coerceIn(0, bitmap.height - 1),
            cropRect.right.coerceIn(1, bitmap.width),
            cropRect.bottom.coerceIn(1, bitmap.height),
        )

        val cropped = Bitmap.createBitmap(
            bitmap,
            safeRect.left,
            safeRect.top,
            safeRect.width(),
            safeRect.height(),
        )

        if (cropped.width == cropped.height) {
            return cropped
        }

        val squareSize = max(cropped.width, cropped.height)
        val squareBitmap = Bitmap.createBitmap(squareSize, squareSize, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(squareBitmap)
        canvas.drawARGB(255, 0, 0, 0)
        val dx = (squareSize - cropped.width) / 2f
        val dy = (squareSize - cropped.height) / 2f
        canvas.drawBitmap(cropped, dx, dy, Paint(Paint.FILTER_BITMAP_FLAG))
        return squareBitmap
    }

    private fun bitmapToNormalizedFloatList(
        bitmap: Bitmap,
        normalizeToSignedUnit: Boolean,
    ): FloatArray {
        val pixels = IntArray(bitmap.width * bitmap.height)
        bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
        val values = FloatArray(pixels.size * 3)
        var index = 0

        for (pixel in pixels) {
            val r = (pixel shr 16) and 0xFF
            val g = (pixel shr 8) and 0xFF
            val b = pixel and 0xFF

            if (normalizeToSignedUnit) {
                values[index++] = ((r / 127.5) - 1.0).toFloat()
                values[index++] = ((g / 127.5) - 1.0).toFloat()
                values[index++] = ((b / 127.5) - 1.0).toFloat()
            } else {
                values[index++] = (r / 255.0).toFloat()
                values[index++] = (g / 255.0).toFloat()
                values[index++] = (b / 255.0).toFloat()
            }
        }

        return values
    }

    private fun computeBlurScore(bitmap: Bitmap): Double {
        if (bitmap.width < 3 || bitmap.height < 3) {
            return 0.0
        }

        val grayscale = IntArray(bitmap.width * bitmap.height)
        val pixels = IntArray(bitmap.width * bitmap.height)
        bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
        for (i in pixels.indices) {
            val pixel = pixels[i]
            val r = (pixel shr 16) and 0xFF
            val g = (pixel shr 8) and 0xFF
            val b = pixel and 0xFF
            grayscale[i] = ((0.299 * r) + (0.587 * g) + (0.114 * b)).toInt()
        }

        var mean = 0.0
        var count = 0
        val laplacianValues = ArrayList<Double>((bitmap.width - 2) * (bitmap.height - 2))

        for (y in 1 until bitmap.height - 1) {
            for (x in 1 until bitmap.width - 1) {
                val center = grayscale[(y * bitmap.width) + x]
                val top = grayscale[((y - 1) * bitmap.width) + x]
                val bottom = grayscale[((y + 1) * bitmap.width) + x]
                val left = grayscale[(y * bitmap.width) + (x - 1)]
                val right = grayscale[(y * bitmap.width) + (x + 1)]
                val laplacian = (4 * center - top - bottom - left - right).toDouble()
                laplacianValues.add(laplacian)
                mean += laplacian
                count += 1
            }
        }

        if (count == 0) {
            return 0.0
        }

        mean /= count.toDouble()
        var variance = 0.0
        for (value in laplacianValues) {
            val delta = value - mean
            variance += delta * delta
        }
        return variance / count.toDouble()
    }
}

internal data class PreprocessedFace(
    val embeddingInput: FloatArray,
    val blurScore: Double,
    val cropWidth: Int,
    val cropHeight: Int,
)
