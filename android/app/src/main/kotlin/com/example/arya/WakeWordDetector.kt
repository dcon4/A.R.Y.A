package com.example.arya

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.content.ContextCompat
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import ai.onnxruntime.TensorInfo
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
        private var N_MELS = 96
        private var N_FRAMES = 16
        private const val FMIN = 0.0f
        private const val FMAX = 8000.0f
        private const val DEBOUNCE_MS = 2000L
    }

    private var audioRecord: AudioRecord? = null
    @Volatile
    var isRunning = false
    private var threshold = 0.5f
    private var lastTriggerTime = 0L
    private var captureThread: Thread? = null
    var sendScoresToDart = false
    private var totalReads = 0
    private var totalBytesRead = 0L

    private lateinit var ortEnv: OrtEnvironment
    private lateinit var ortSession: OrtSession
    private lateinit var hannWindow: FloatArray
    private lateinit var melFilterBank: Array<FloatArray>
    private val ringBuffer = Array(N_FRAMES) { FloatArray(N_MELS) }
    private var ringIndex = 0
    private var framesCollected = 0
    private var inputName = "input"
    private var outputName = "output"

    private fun postToMainThread(action: () -> Unit) {
        Handler(Looper.getMainLooper()).post(action)
    }

    private fun logToDart(level: String, message: String) {
        val full = "[WakeWordDetector] [$level] $message"
        if (level == "ERROR") Log.e(TAG, message) else Log.i(TAG, message)
        postToMainThread {
            flutterEngine?.dartExecutor?.binaryMessenger?.let {
                try {
                    MethodChannel(it, "arya.wake_word").invokeMethod("nativeLog", full)
                } catch (_: Exception) {}
            }
        }
    }

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

            val inputInfo = ortSession.getInputInfo()
            val tensorInfo = inputInfo[inputName]?.info
            val shapeStr = tensorInfo?.toString() ?: "unknown"

            // Read actual model shape to set N_FRAMES and N_MELS dynamically
            try {
                val shape = (tensorInfo as? ai.onnxruntime.TensorInfo)?.shape
                if (shape != null && shape.size >= 3) {
                    N_FRAMES = shape[1].toInt().coerceAtLeast(1)
                    N_MELS = shape[2].toInt().coerceAtLeast(1)
                    logToDart("INFO", "Using model shape: frames=$N_FRAMES, mels=$N_MELS")
                }
            } catch (_: Exception) {
                logToDart("WARN", "Could not parse model shape, using defaults frames=$N_FRAMES, mels=$N_MELS")
            }

            logToDart("INFO", "Model: input=$inputName ($shapeStr), output=$outputName")

            computeHannWindow()
            computeMelFilterBank()
            logToDart("INFO", "WakeWordDetector initialized successfully (frames=$N_FRAMES, mels=$N_MELS)")
            true
        } catch (e: Exception) {
            logToDart("ERROR", "Failed to initialize: ${e.message}")
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
        if (isRunning) {
            logToDart("INFO", "Already running, ignoring start")
            return
        }
        if (!::ortEnv.isInitialized) {
            logToDart("ERROR", "WakeWordDetector not initialized")
            return
        }
        if (ContextCompat.checkSelfPermission(
                context ?: run {
                    logToDart("ERROR", "Context is null")
                    return
                },
                Manifest.permission.RECORD_AUDIO
            ) != PackageManager.PERMISSION_GRANTED) {
            logToDart("ERROR", "RECORD_AUDIO permission not granted")
            return
        }

        this.threshold = thresholdValue
        isRunning = true
        ringIndex = 0
        framesCollected = 0
        totalReads = 0
        totalBytesRead = 0L

        val bufferSize = AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        ).coerceAtLeast(N_FFT * 2)

        logToDart("INFO", "AudioRecord bufferSize=$bufferSize")

        audioRecord = AudioRecord(
            MediaRecorder.AudioSource.MIC,
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            bufferSize
        )

        if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
            logToDart("ERROR", "AudioRecord failed to initialize (state=${audioRecord?.state})")
            isRunning = false
            audioRecord?.release()
            audioRecord = null
            return
        }

        try {
            audioRecord?.startRecording()
            logToDart("INFO", "AudioRecord started recording")
        } catch (e: Exception) {
            logToDart("ERROR", "Failed to start recording: ${e.message}")
            isRunning = false
            audioRecord?.release()
            audioRecord = null
            return
        }

        captureThread = Thread {
            try {
                val buffer = ShortArray(HOP_LENGTH * 4)
                Log.i(TAG, "Capture thread running")
                logToDart("INFO", "Capture thread started")
                var consecutiveEmptyReads = 0
                while (isRunning) {
                    if (audioRecord == null) {
                        logToDart("ERROR", "audioRecord became null during capture")
                        break
                    }
                    val read = audioRecord!!.read(buffer, 0, buffer.size)
                    if (read > 0) {
                        consecutiveEmptyReads = 0
                        totalReads++
                        totalBytesRead += read
                        val frame = buffer.copyOf(minOf(read, HOP_LENGTH))
                        processFrame(frame)
                    } else if (read == 0) {
                        consecutiveEmptyReads++
                        if (consecutiveEmptyReads > 100) {
                            logToDart("WARN", "100 consecutive empty reads")
                            consecutiveEmptyReads = 0
                        }
                    } else {
                        logToDart("ERROR", "AudioRecord.read returned $read")
                        break
                    }
                }
                logToDart("INFO", "Capture thread exiting (totalReads=$totalReads, bytes=$totalBytesRead)")
            } catch (e: Exception) {
                Log.e(TAG, "Capture thread crashed", e)
                logToDart("ERROR", "Capture thread crashed: ${e.message}")
            }
        }
        captureThread?.start()
        logToDart("INFO", "WakeWordDetector started (threshold=$threshold)")
    }

    fun stop() {
        logToDart("INFO", "Stopping (totalReads=$totalReads, bytes=$totalBytesRead, framesCollected=$framesCollected)")
        isRunning = false
        captureThread?.join(500)
        try {
            audioRecord?.stop()
        } catch (_: Exception) {}
        audioRecord?.release()
        audioRecord = null
        logToDart("INFO", "WakeWordDetector stopped")
    }

    fun pause() {
        logToDart("INFO", "Pausing — releasing mic for speech recognition")
        isRunning = false
        captureThread?.join(500)
        try {
            audioRecord?.stop()
        } catch (_: Exception) {}
        audioRecord?.release()
        audioRecord = null
    }

    fun resume(thresholdValue: Float) {
        logToDart("INFO", "Resuming after speech recognition (threshold=$thresholdValue)")
        this.threshold = thresholdValue
        startAudioCapture()
    }

    private fun startAudioCapture() {
        if (!::ortEnv.isInitialized) {
            logToDart("ERROR", "Cannot resume — not initialized")
            return
        }
        if (ContextCompat.checkSelfPermission(
                context ?: return,
                Manifest.permission.RECORD_AUDIO
            ) != PackageManager.PERMISSION_GRANTED) {
            logToDart("ERROR", "Cannot resume — RECORD_AUDIO not granted")
            return
        }

        isRunning = true
        ringIndex = 0
        framesCollected = 0
        totalReads = 0
        totalBytesRead = 0L

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

        if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
            logToDart("ERROR", "AudioRecord failed to initialize on resume")
            isRunning = false
            audioRecord?.release()
            audioRecord = null
            return
        }

        try {
            audioRecord?.startRecording()
        } catch (e: Exception) {
            logToDart("ERROR", "Failed to start recording on resume: ${e.message}")
            isRunning = false
            audioRecord?.release()
            audioRecord = null
            return
        }

        captureThread = Thread {
            try {
                val buffer = ShortArray(HOP_LENGTH * 4)
                while (isRunning) {
                    if (audioRecord == null) break
                    val read = audioRecord!!.read(buffer, 0, buffer.size)
                    if (read > 0) {
                        totalReads++
                        totalBytesRead += read
                        val frame = buffer.copyOf(minOf(read, HOP_LENGTH))
                        processFrame(frame)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Capture thread crashed after resume", e)
                logToDart("ERROR", "Capture thread crashed after resume: ${e.message}")
            }
        }
        captureThread?.start()
        logToDart("INFO", "WakeWordDetector resumed")
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
            val flatInput = FloatArray(N_FRAMES * N_MELS)
            var idx = 0
            for (t in 0 until N_FRAMES) {
                val bufIdx = (ringIndex + t) % N_FRAMES
                for (m in 0 until N_MELS) {
                    flatInput[idx++] = ringBuffer[bufIdx][m]
                }
            }

            val minVal = flatInput.minOrNull() ?: 0f
            val maxVal = flatInput.maxOrNull() ?: 0f

            val tensor = OnnxTensor.createTensor(ortEnv, FloatBuffer.wrap(flatInput), longArrayOf(1, N_FRAMES.toLong(), N_MELS.toLong()))
            val results = ortSession.run(mapOf(inputName to tensor))

            val outputObj = results.get(outputName)
            var score = 0f

            // Unwrap java.util.Optional if present (ORT 1.20.0 returns Optional for
            // optional model outputs, e.g. output "39" of the openWakeWord model)
            val outputTensor = if (outputObj is java.util.Optional<*>) outputObj.orElse(null) else outputObj

            if (outputTensor is OnnxTensor) {
                try {
                    val fb = outputTensor.getFloatBuffer()
                    if (fb.hasRemaining()) score = fb.get()
                } catch (e1: Exception) {
                    try {
                        val obj = outputTensor.getValue()
                        when (obj) {
                            is Array<*> -> {
                                val row = obj[0]
                                if (row is FloatArray) score = row[0]
                                else if (row is DoubleArray) score = row[0].toFloat()
                                else if (row is Array<*>) score = (row[0] as? Number)?.toFloat() ?: 0f
                            }
                            is FloatArray -> score = obj[0]
                            is DoubleArray -> score = obj[0].toFloat()
                            is Number -> score = obj.toFloat()
                            is java.nio.FloatBuffer -> if (obj.hasRemaining()) score = obj.get()
                        }
                    } catch (_: Exception) {}
                }
            } else {
                val rawOutput = outputTensor?.let {
                    if (it is OnnxTensor) {
                        try {
                            val fb = it.getFloatBuffer()
                            if (fb.hasRemaining()) return@let fb.get()
                        } catch (_: Exception) {}
                    }
                    null
                }
                if (rawOutput != null) {
                    score = rawOutput
                } else {
                    val rawGet = outputTensor?.let {
                        if (it is OnnxTensor) it.getValue() else it
                    }
                    if (rawGet is Array<*>) {
                        val batch = rawGet[0]
                        if (batch is FloatArray) {
                            score = batch[0]
                        } else if (batch is Array<*>) {
                            score = (batch[0] as? Number)?.toFloat() ?: 0f
                        } else if (batch is Number) {
                            score = batch.toFloat()
                        }
                    } else if (rawGet is FloatArray) {
                        score = rawGet[0]
                    } else if (rawGet is Number) {
                        score = rawGet.toFloat()
                    }
                }
            }

            tensor.close()
            results.close()

            val now = System.currentTimeMillis()

            if (sendScoresToDart || maxVal > 0.01f) {
                val outputType = outputTensor?.javaClass?.name ?: "null"
                logToDart("SCORE", "score=%.6f input_range=[%.4f..%.4f] output_type=%s".format(score, minVal, maxVal, outputType))
            }

            if (sendScoresToDart) {
                postToMainThread {
                    flutterEngine?.dartExecutor?.binaryMessenger?.let {
                        MethodChannel(it, "arya.wake_word").invokeMethod("inferenceScore", score.toDouble())
                    }
                }
            }

            if (score > threshold && (now - lastTriggerTime) > DEBOUNCE_MS) {
                lastTriggerTime = now
                logToDart("DETECT", "Wake word detected! score=$score")
                postToMainThread {
                    flutterEngine?.dartExecutor?.binaryMessenger?.let {
                        MethodChannel(it, "arya.wake_word").invokeMethod("wakeWordDetected", null)
                    }
                }
            }
        } catch (e: Exception) {
            logToDart("ERROR", "Inference error: ${e.message}")
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
