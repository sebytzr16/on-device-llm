package app.ondevicellm.ondevice_llm

import android.content.Context
import android.net.Uri
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

class OnDeviceOcr(context: Context, messenger: BinaryMessenger) {
    init {
        MethodChannel(messenger, "ondevice_llm/ocr").setMethodCallHandler { call, result ->
            if (call.method != "recognize") { result.notImplemented(); return@setMethodCallHandler }
            try {
                val path = requireNotNull(call.argument<String>("path"))
                val file = File(path).canonicalFile
                // Dart supplies only copied attachments and its rendered page
                // cache. Native recognition has no URL or network input path.
                require(file.isFile)
                val image = InputImage.fromFilePath(context, Uri.fromFile(file))
                val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
                recognizer.process(image)
                    .addOnSuccessListener { text ->
                        val elements = text.textBlocks.flatMap { it.lines }.flatMap { it.elements }
                        val scored = elements.filter { it.confidence > 0 && it.text.isNotEmpty() }
                        val weight = scored.sumOf { it.text.length }
                        val confidence = if (weight > 0) scored.sumOf { it.confidence.toDouble() * it.text.length } / weight else null
                        // Line boxes let Dart put a receipt's amount column
                        // back next to its labels (OcrLayout.paired).
                        val lines = text.textBlocks.flatMap { it.lines }.mapNotNull { line ->
                            val box = line.boundingBox ?: return@mapNotNull null
                            mapOf(
                                "text" to line.text,
                                "left" to box.left, "top" to box.top,
                                "right" to box.right, "bottom" to box.bottom,
                                "angle" to line.angle.toDouble(),
                            )
                        }
                        result.success(mapOf("text" to text.text, "confidence" to confidence, "lines" to lines))
                    }
                    .addOnFailureListener { error -> result.error("ocr", error.message, null) }
                    .addOnCompleteListener { recognizer.close() }
            } catch (error: Exception) { result.error("ocr", error.message, null) }
        }
    }
}
