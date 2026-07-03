package com.example.arya

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.util.Log
import androidx.core.content.ContextCompat
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.InputStream
import java.nio.FloatBuffer
import kotlin.math.cos
import kotlin.math.log10
import kotlin.math.PI
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

class WakeWordDetector(private val flutterEngine: FlutterEngine?, private val context: Context?) {
    companion object {
        private const val TAG = "WakeWordDetector"
        private const val SAMPLE_RATE = 16000
        private const val N_FFT = 512
        private const val HOP_LENGTH = 160
        private const val WIN_LENGTH = 400
        private const val N_MELS = 64
        private const val N_FRAMES = 128
        private const val FMIN = 0.0f
        private const val FMAX = 8000.0f
        private const val DEBOUNCE_MS = 2000L
    }

    private var audioRecord: AudioRecord? = null
    private var isRunning = false
    private var threshold = 0.5f
    private var lastTriggerTime = 0L
    private var captureThread: Thread? = null
    var sendScoresToDart = false

    private lateinit var ortEnv: OrtEnvironment
    private lateinit var ortSession: OrtSession
    private lateinit var hannWindow: FloatArray
    private lateinit var melFilterBank: Array<FloatArray>
    private val ringBuffer = Array(N_FRAMES) { FloatArray(N_MELS) }
    private var ringIndex = 0
    private var framesCollected = 0
    private var inputName = "input"
    private var outputName = "output"

    fun initialize(modelStream: InputStream): Boolean {
        return try {
            ortEnv = OrtEnvironment.getEnvironment()
            val options = OrtSession.SessionOptions()
            ortSession = ortEnv.createSession(modelStream.readBytes(), options)

            // Read input/output names from the model
            if (ortSession.inputNames.isNotEmpty()) {
                inputName = ortSession.inputNames.iterator().next()
            }
            if (ortSession.outputNames.isNotEmpty()) {
                outputName = ortSession.outputNames.iterator().next()
            }

            computeHannWindow()
            computeMelFilterBank()
            Log.i(TAG, "WakeWordDetector initialized (input=$inputName, output=$outputName)")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize WakeWordDetector", e)
            false
        }
    }

    private fun computeHannWindow() {
        hannWindow = FloatArray(WIN_LENGTH)
        for (i in 0 until WIN_LENGTH) {
            hannWindow[i] = (0.5 * (1.0 - cos(2.0 * PI * i / (WIN_LENGTH - 1)))).toFloat()
        }
    }

    private fun computeMelFilterBank() {
        val nFftBins = N_FFT / 2 + 1
        val melLow = hzToMel(FMIN.toDouble())
        val melHigh = hzToMel(FMAX.toDouble())
        val melPoints = FloatArray(N_MELS + 2)
        for (i in 0 until N_MELS + 2) {
            melPoints[i] = melToHz(melLow + (melHigh - melLow) * i / (N_MELS + 1)).toFloat()
        }
        val fftBins = FloatArray(nFftBins) { i -> i.toFloat() * SAMPLE_RATE / N_FFT }

        melFilterBank = Array(N_MELS) { FloatArray(nFftBins) }
        for (m in 0 until N_MELS) {
            for (k in 0 until nFftBins) {
                val freq = fftBins[k]
                if (freq >= melPoints[m] && freq <= melPoints[m + 1]) {
                    melFilterBank[m][k] = (freq - melPoints[m]) / (melPoints[m + 1] - melPoints[m])
                } else if (freq >= melPoints[m + 1] && freq <= melPoints[m + 2]) {
                    melFilterBank[m][k] = (melPoints[m + 2] - freq) / (melPoints[m + 2] - melPoints[m + 1])
                }
            }
        }
    }

    private fun hzToMel(hz: Double): Double = 2595.0 * log10(1.0 + hz / 700.0)

    private fun melToHz(mel: Double): Double = 700.0 * (10.0.pow(mel / 2595.0) - 1.0)

    fun start(thresholdValue: Float) {
        if (isRunning) return
        if (!::ortEnv.isInitialized) {
            Log.e(TAG, "WakeWordDetector not initialized")
            return
        }
        if (ContextCompat.checkSelfPermission(
                context ?: return,
                Manifest.permission.RECORD_AUDIO
            ) != PackageManager.PERMISSION_GRANTED) {
            Log.e(TAG, "RECORD_AUDIO permission not granted")
            return
        }

        this.threshold = thresholdValue
        isRunning = true
        ringIndex = 0
        framesCollected = 0

        val bufferSize = AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        ).coerceAtLeast(N_FFT * 2)

        audioRecord = AudioRecord(
            MediaRecorder.AudioSource.MIC,
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            bufferSize
        )

        try {
            audioRecord?.startRecording()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start recording", e)
            isRunning = false
            return
        }

        captureThread = Thread {
            val buffer = ShortArray(HOP_LENGTH * 2)
            while (isRunning) {
                val read = audioRecord?.read(buffer, 0, HOP_LENGTH) ?: 0
                if (read > 0) {
                    val frame = buffer.copyOf(read)
                    processFrame(frame)
                }
            }
        }
        captureThread?.start()
        Log.i(TAG, "WakeWordDetector started")
    }

    fun stop() {
        isRunning = false
        captureThread?.join(500)
        try {
            audioRecord?.stop()
        } catch (_: Exception) {}
        audioRecord?.release()
        audioRecord = null
        Log.i(TAG, "WakeWordDetector stopped")
    }

    private fun processFrame(samples: ShortArray) {
        val frame = zeroPad(samples, N_FFT)
        val windowed = FloatArray(N_FFT)
        for (i in 0 until WIN_LENGTH) {
            windowed[i] = frame[i].toFloat() / Short.MAX_VALUE * hannWindow[i]
        }

        val fft = realFft(windowed)
        val magnitude = FloatArray(N_FFT / 2 + 1)
        for (i in 0 until N_FFT / 2 + 1) {
            magnitude[i] = sqrt(fft[i].first * fft[i].first + fft[i].second * fft[i].second).toFloat()
        }

        for (m in 0 until N_MELS) {
            var energy = 0.0f
            for (k in 0 until N_FFT / 2 + 1) {
                energy += magnitude[k] * melFilterBank[m][k]
            }
            ringBuffer[ringIndex][m] = log10(energy.coerceAtLeast(1e-10f))
        }

        ringIndex = (ringIndex + 1) % N_FRAMES
        if (framesCollected < N_FRAMES) framesCollected++

        if (framesCollected >= N_FRAMES) {
            runInference()
        }
    }

    private fun runInference() {
        try {
            val input = Array(1) { Array(N_FRAMES) { FloatArray(N_MELS) } }
            for (t in 0 until N_FRAMES) {
                val bufIdx = (ringIndex + t) % N_FRAMES
                for (m in 0 until N_MELS) {
                    input[0][t][m] = ringBuffer[bufIdx][m]
                }
            }

            val flatInput = FloatArray(N_FRAMES * N_MELS)
            var idx = 0
            for (t in 0 until N_FRAMES) {
                for (m in 0 until N_MELS) {
                    flatInput[idx++] = input[0][t][m]
                }
            }

            val tensor = OnnxTensor.createTensor(ortEnv, FloatBuffer.wrap(flatInput), longArrayOf(1, N_FRAMES.toLong(), N_MELS.toLong()))
            val results = ortSession.run(mapOf(inputName to tensor))
            val output = results.get(outputName)?.get() as? Array<*>
            val score = output?.get(0)?.let { (it as? Array<*>)?.get(0) as? Float } ?: 0f

            tensor.close()
            results.close()

            val now = System.currentTimeMillis()

            if (sendScoresToDart) {
                flutterEngine?.dartExecutor?.binaryMessenger?.let {
                    MethodChannel(it, "arya.wake_word").invokeMethod("inferenceScore", score.toDouble())
                }
            }

            if (score > threshold && (now - lastTriggerTime) > DEBOUNCE_MS) {
                lastTriggerTime = now
                Log.i(TAG, "Wake word detected! score=$score")
                flutterEngine?.dartExecutor?.binaryMessenger?.let {
                    MethodChannel(it, "arya.wake_word").invokeMethod("wakeWordDetected", null)
                }
            } else {
                Log.v(TAG, "Inference score=$score (threshold=$threshold)")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Inference error", e)
        }
    }

    private fun zeroPad(arr: ShortArray, size: Int): ShortArray {
        val result = ShortArray(size)
        val copyLen = minOf(arr.size, size)
        System.arraycopy(arr, 0, result, 0, copyLen)
        return result
    }

    private fun realFft(data: FloatArray): Array<Pair<Double, Double>> {
        val n = data.size
        val real = data.map { it.toDouble() }.toDoubleArray()
        val imag = DoubleArray(n)

        fft(real, imag, false)

        return Array(n / 2 + 1) { Pair(real[it], imag[it]) }
    }

    private fun fft(real: DoubleArray, imag: DoubleArray, inverse: Boolean) {
        val n = real.size
        var bits = 0
        while (1 shl bits < n) bits++

        for (i in 0 until n) {
            var j = Integer.reverse(i) ushr (32 - bits)
            if (j > i) {
                var tmp = real[i]
                real[i] = real[j]
                real[j] = tmp
                tmp = imag[i]
                imag[i] = imag[j]
                imag[j] = tmp
            }
        }

        var len = 2
        while (len <= n) {
            val ang = 2.0 * PI / len * (if (inverse) -1 else 1)
            val wlenReal = cos(ang)
            val wlenImag = sin(ang)
            for (i in 0 until n step len) {
                var wReal = 1.0
                var wImag = 0.0
                for (j in 0 until len / 2) {
                    val uReal = real[i + j]
                    val uImag = imag[i + j]
                    val tReal = real[i + j + len / 2] * wReal - imag[i + j + len / 2] * wImag
                    val tImag = real[i + j + len / 2] * wImag + imag[i + j + len / 2] * wReal
                    real[i + j] = uReal + tReal
                    imag[i + j] = uImag + tImag
                    real[i + j + len / 2] = uReal - tReal
                    imag[i + j + len / 2] = uImag - tImag
                    val nextWReal = wReal * wlenReal - wImag * wlenImag
                    wImag = wReal * wlenImag + wImag * wlenReal
                    wReal = nextWReal
                }
            }
            len = len shl 1
        }

        if (inverse) {
            for (i in 0 until n) {
                real[i] /= n
                imag[i] /= n
            }
        }
    }

    fun destroy() {
        stop()
        try { if (::ortSession.isInitialized) ortSession.close() } catch (_: Exception) {}
    }
}
