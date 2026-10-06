package com.jjolmo.gallery

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val worker = Executors.newFixedThreadPool(2)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "gallery/video_frame")
            .setMethodCallHandler { call, result ->
                val source = call.argument<String>("source")!!
                val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()
                val size = call.argument<Int>("size") ?: 320
                worker.execute {
                    val bytes = try { frame(source, headers, size) } catch (e: Exception) { null }
                    runOnUiThread { result.success(bytes) }
                }
            }
    }

    // A JPEG of an early frame, scaled to fit [size]. For http(s) sources the
    // retriever only fetches the byte ranges it needs, not the whole video.
    private fun frame(source: String, headers: Map<String, String>, size: Int): ByteArray? {
        val retriever = MediaMetadataRetriever()
        try {
            if (source.startsWith("http://") || source.startsWith("https://")) {
                retriever.setDataSource(source, headers)
            } else {
                retriever.setDataSource(source)
            }
            val raw = retriever.getFrameAtTime(1_000_000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                ?: retriever.frameAtTime
                ?: return null
            val scale = size.toFloat() / maxOf(raw.width, raw.height)
            val bitmap = if (scale < 1f) {
                Bitmap.createScaledBitmap(raw, (raw.width * scale).toInt(), (raw.height * scale).toInt(), true)
            } else {
                raw
            }
            val out = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.JPEG, 80, out)
            return out.toByteArray()
        } finally {
            retriever.release()
        }
    }
}
