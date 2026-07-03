package com.example.arya

import android.content.Context
import android.content.Intent
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.net.Uri
import android.util.Log
import android.view.KeyEvent
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "arya.mic"
    private val SAVE_DIRECTORY_CHANNEL = "arya.save_directory"
    private val WAKE_WORD_CHANNEL = "arya.wake_word"
    private var saveDirectoryResult: MethodChannel.Result? = null
    private var wakeWordDetector: WakeWordDetector? = null
    private var mediaSession: MediaSession? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        setupMediaSession()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startForegroundService" -> {
                    AryaForegroundService.start(this)
                    result.success(true)
                }
                "stopForegroundService" -> {
                    AryaForegroundService.stop(this)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SAVE_DIRECTORY_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickDirectory" -> {
                    saveDirectoryResult = result
                    pickDirectory()
                }
                "writeFile" -> {
                    val uriString = call.argument<String>("uri")
                    val fileName = call.argument<String>("fileName")
                    val content = call.argument<String>("content")
                    if (uriString != null && fileName != null && content != null) {
                        try {
                            writeFileToUri(uriString, fileName, content)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("WRITE_FAILED", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGS", "uri, fileName, and content are required", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WAKE_WORD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val threshold = (call.argument<Double>("threshold") ?: 0.5).toFloat()
                    if (wakeWordDetector == null) {
                        val modelStream = assets.open("wakeword/hey_rhasspy.onnx")
                        wakeWordDetector = WakeWordDetector(flutterEngine, this)
                        val ok = wakeWordDetector!!.initialize(modelStream)
                        if (!ok) {
                            result.error("INIT_FAILED", "Failed to initialize wake word detector", null)
                            return@setMethodCallHandler
                        }
                    }
                    wakeWordDetector?.start(threshold)
                    result.success(true)
                }
                "stop" -> {
                    wakeWordDetector?.stop()
                    result.success(true)
                }
                "setThreshold" -> {
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun setupMediaSession() {
        mediaSession = MediaSession(this, "arya_bluetooth_session")
        mediaSession?.setCallback(object : MediaSession.Callback() {
            override fun onMediaButtonEvent(mediaButtonIntent: Intent): Boolean {
                val event = mediaButtonIntent.getParcelableExtra<KeyEvent>(Intent.EXTRA_KEY_EVENT)
                if (event?.action == KeyEvent.ACTION_DOWN &&
                    event.keyCode == KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
                ) {
                    Log.i("MainActivity", "Bluetooth media button pressed via MediaSession")
                    val prefs = applicationContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    val enabled = prefs.getBoolean("bluetooth_mic_control", false)
                    if (enabled) {
                        flutterEngine?.dartExecutor?.binaryMessenger?.let {
                            MethodChannel(it, "arya.bluetooth_mic_toggle").invokeMethod("toggleMic", null)
                        }
                    }
                    return true
                }
                return super.onMediaButtonEvent(mediaButtonIntent)
            }
        })
        mediaSession?.setPlaybackState(
            PlaybackState.Builder()
                .setActions(PlaybackState.ACTION_PLAY_PAUSE)
                .setState(PlaybackState.STATE_NONE, PlaybackState.PLAYBACK_POSITION_UNKNOWN, 0f)
                .build()
        )
        mediaSession?.setFlags(MediaSession.FLAG_HANDLES_MEDIA_BUTTONS or MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS)
        mediaSession?.isActive = true
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleMicIntent(intent)
    }

    override fun onStart() {
        super.onStart()
        handleMicIntent(intent)
    }

    override fun onPause() {
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
    }

    override fun onDestroy() {
        super.onDestroy()
        mediaSession?.isActive = false
        mediaSession?.release()
        wakeWordDetector?.destroy()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == PICK_DIRECTORY_REQUEST) {
            if (resultCode == RESULT_OK && data?.data != null) {
                val uri = data.data!!
                contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                saveDirectoryResult?.success(uri.toString())
            } else {
                saveDirectoryResult?.success(null)
            }
            saveDirectoryResult = null
        }
    }

    private fun pickDirectory() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        startActivityForResult(intent, PICK_DIRECTORY_REQUEST)
    }

    private fun handleMicIntent(intent: Intent?) {
        if (intent?.getBooleanExtra("start_mic", false) == true) {
            flutterEngine?.dartExecutor?.binaryMessenger?.let {
                MethodChannel(it, "arya.mic_trigger").invokeMethod("startListening", null)
            }
        }
    }

    private fun writeFileToUri(uriString: String, fileName: String, content: String) {
        val treeUri = Uri.parse(uriString)
        val documentFile = DocumentFile.fromTreeUri(this, treeUri)
        var file = documentFile?.findFile(fileName)
        if (file == null || !file.exists()) {
            file = documentFile?.createFile("text/plain", fileName)
        }
        val outputStream = contentResolver.openOutputStream(file!!.uri)
        outputStream?.write(content.toByteArray(Charsets.UTF_8))
        outputStream?.close()
    }

    companion object {
        private const val PICK_DIRECTORY_REQUEST = 9001
    }
}
