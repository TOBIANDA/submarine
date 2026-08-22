package com.submarine

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.ryanheise.audioservice.AudioServiceActivity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.schabi.newpipe.extractor.NewPipe
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.downloader.Downloader
import org.schabi.newpipe.extractor.downloader.Request as NewPipeRequest
import org.schabi.newpipe.extractor.downloader.Response as NewPipeResponse
import org.schabi.newpipe.extractor.services.youtube.extractors.YoutubeStreamExtractor
import org.schabi.newpipe.extractor.stream.StreamInfoItem
import java.io.IOException

class MainActivity: AudioServiceActivity() {
    private val BATTERY_CHANNEL = "com.submarine/battery"
    private val EXTRACTOR_CHANNEL = "com.submarine/extractor"
    private var isNewPipeInitialized = false

    private fun initNewPipe() {
        if (isNewPipeInitialized) return
        try {
            val okHttpClient = OkHttpClient.Builder().build()
            val customDownloader = object : Downloader() {
                @Throws(IOException::class)
                override fun execute(request: NewPipeRequest): NewPipeResponse {
                    val builder = Request.Builder().url(request.url())
                    
                    for ((key, value) in request.headers()) {
                        builder.addHeader(key, value.joinToString(","))
                    }
                    
                    if (request.httpMethod().equals("POST", ignoreCase = true)) {
                        val body = request.dataToSend() ?: ByteArray(0)
                        builder.post(body.toRequestBody(null))
                    } else {
                        builder.get()
                    }
                    
                    val response = okHttpClient.newCall(builder.build()).execute()
                    val responseBody = response.body?.string() ?: ""
                    val responseHeaders = mutableMapOf<String, List<String>>()
                    for (name in response.headers.names()) {
                        responseHeaders[name] = response.headers(name)
                    }
                    
                    return NewPipeResponse(
                        response.code,
                        response.message,
                        responseHeaders,
                        responseBody,
                        response.request.url.toString()
                    )
                }
            }
            NewPipe.init(customDownloader)
            isNewPipeInitialized = true
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        initNewPipe()

        // Battery Optimization Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BATTERY_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestBatteryExemption" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val powerManager = getSystemService(POWER_SERVICE) as PowerManager
                            if (!powerManager.isIgnoringBatteryOptimizations(packageName)) {
                                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                    data = Uri.parse("package:$packageName")
                                }
                                startActivity(intent)
                            }
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        try {
                            val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                            startActivity(intent)
                            result.success(true)
                        } catch (e2: Exception) {
                            result.error("BATTERY_ERROR", e2.message, null)
                        }
                    }
                }
                "isBatteryOptimized" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val powerManager = getSystemService(POWER_SERVICE) as PowerManager
                        result.success(!powerManager.isIgnoringBatteryOptimizations(packageName))
                    } else {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // NewPipeExtractor Stream Channel & Radio Automix
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, EXTRACTOR_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAudioStreamUrl" -> {
                    val videoId = call.argument<String>("videoId")
                    if (videoId.isNullOrEmpty()) {
                        result.error("INVALID_ID", "Video ID is null or empty", null)
                        return@setMethodCallHandler
                    }

                    CoroutineScope(Dispatchers.IO).launch {
                        try {
                            initNewPipe()
                            val url = "https://www.youtube.com/watch?v=$videoId"
                            val extractor = ServiceList.YouTube.getStreamExtractor(url) as YoutubeStreamExtractor
                            extractor.fetchPage()
                            
                            val audioStreams = extractor.audioStreams
                            if (audioStreams.isNotEmpty()) {
                                // Prioritize M4A (itag 140 / AAC) for seamless Android ExoPlayer playback without silent gaps
                                val m4aStream = audioStreams.firstOrNull { 
                                    it.getFormat()?.getName()?.contains("m4a", ignoreCase = true) == true ||
                                    it.itag == 140
                                }
                                val chosenStream = m4aStream ?: audioStreams.maxByOrNull { it.averageBitrate } ?: audioStreams[0]
                                val streamUrl = chosenStream.content
                                val formatName = chosenStream.getFormat()?.getName() ?: "m4a"
                                
                                withContext(Dispatchers.Main) {
                                    result.success(mapOf(
                                        "url" to streamUrl,
                                        "bitrate" to chosenStream.averageBitrate,
                                        "format" to formatName
                                    ))
                                }
                            } else {
                                withContext(Dispatchers.Main) {
                                    result.error("NO_STREAMS", "No audio streams found", null)
                                }
                            }
                        } catch (e: Exception) {
                            withContext(Dispatchers.Main) {
                                result.error("EXTRACT_ERROR", e.message, null)
                            }
                        }
                    }
                }

                "getRadioTracks" -> {
                    val videoId = call.argument<String>("videoId")
                    val limit = call.argument<Int>("limit") ?: 10
                    if (videoId.isNullOrEmpty()) {
                        result.error("INVALID_ID", "Video ID is null or empty", null)
                        return@setMethodCallHandler
                    }

                    CoroutineScope(Dispatchers.IO).launch {
                        try {
                            initNewPipe()
                            val url = "https://www.youtube.com/watch?v=$videoId"
                            val extractor = ServiceList.YouTube.getStreamExtractor(url) as YoutubeStreamExtractor
                            extractor.fetchPage()

                            val list = mutableListOf<Map<String, Any?>>()
                            val related = extractor.relatedItems
                            if (related != null && related.items != null) {
                                val blacklist = listOf(
                                    "full album", "album lengkap", "compilation", "kompilasi",
                                    "1 hour", "2 hour", "3 hour", "1 jam", "2 jam",
                                    "nonstop", "non stop", "discography", "best songs of",
                                    "top 50", "top 100", "podcast", "audiobook"
                                )

                                for (item in related.items) {
                                    if (item is StreamInfoItem) {
                                        val itemUrl = item.url ?: ""
                                        val vId = if (itemUrl.contains("v=")) {
                                            itemUrl.substringAfter("v=").substringBefore("&")
                                        } else if (itemUrl.contains("youtu.be/")) {
                                            itemUrl.substringAfter("youtu.be/").substringBefore("?")
                                        } else {
                                            ""
                                        }

                                        val titleLower = (item.name ?: "").lowercase()
                                        val isAlbum = blacklist.any { titleLower.contains(it) }
                                        val dur = item.duration.toInt()
                                        val isSongDuration = dur == 0 || (dur in 45..660)

                                        if (vId.isNotEmpty() && vId != videoId && !isAlbum && isSongDuration) {
                                            val thumb = item.thumbnails?.firstOrNull()?.url 
                                                ?: "https://i.ytimg.com/vi/$vId/hqdefault.jpg"
                                            list.add(mapOf(
                                                "videoId" to vId,
                                                "title" to (item.name ?: "Unknown Title"),
                                                "channelTitle" to (item.uploaderName ?: "Unknown Artist"),
                                                "thumbnailUrl" to thumb,
                                                "durationSeconds" to dur
                                            ))
                                            if (list.size >= limit) break
                                        }
                                    }
                                }
                            }

                            withContext(Dispatchers.Main) {
                                result.success(list)
                            }
                        } catch (e: Exception) {
                            withContext(Dispatchers.Main) {
                                result.error("RADIO_ERROR", e.message, null)
                            }
                        }
                    }
                }

                else -> result.notImplemented()
            }
        }
    }
}
