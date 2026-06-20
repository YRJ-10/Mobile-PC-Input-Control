package com.example.flutter_client

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.net.DatagramPacket
import java.net.DatagramSocket

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.mobilepcmedia/audio"
    
    private var udpSocket: DatagramSocket? = null
    private var audioTrack: AudioTrack? = null
    private var isReceiving = false
    private var audioThread: Thread? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "startAudioReceiver") {
                startAudioReceiver()
                result.success(null)
            } else if (call.method == "stopAudioReceiver") {
                stopAudioReceiver()
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun startAudioReceiver() {
        if (isReceiving) return
        isReceiving = true

        val sampleRate = 16000
        val minBufferSize = AudioTrack.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )

        audioTrack = AudioTrack.Builder()
            .setAudioAttributes(AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build())
            .setAudioFormat(AudioFormat.Builder()
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setSampleRate(sampleRate)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                .build())
            .setBufferSizeInBytes(minBufferSize)
            .setTransferMode(AudioTrack.MODE_STREAM)
            .setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
            .build()

        audioTrack?.play()

        audioThread = Thread {
            try {
                udpSocket = DatagramSocket(8081)
                val buffer = ByteArray(minBufferSize * 2) // Gunakan buffer sedikit lebih besar untuk UDP
                val packet = DatagramPacket(buffer, buffer.size)

                while (isReceiving) {
                    udpSocket?.receive(packet)
                    // Tulis langsung ke AudioTrack secara real-time
                    audioTrack?.write(packet.data, 0, packet.length)
                }
            } catch (e: Exception) {
                e.printStackTrace()
            } finally {
                udpSocket?.close()
                udpSocket = null
            }
        }
        audioThread?.start()
    }

    private fun stopAudioReceiver() {
        isReceiving = false
        udpSocket?.close()
        audioTrack?.stop()
        audioTrack?.release()
        audioTrack = null
    }
}
