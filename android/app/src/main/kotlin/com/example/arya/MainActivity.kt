package com.example.arya

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import android.util.Log
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "arya.mic"
    private val SAVE_DIRECTORY_CHANNEL = "arya.save_directory"
    private val WAKE_WORD_CHANNEL = "arya.wake_word"
    private val TTS_CHANNEL = "arya.tts"
    private var saveDirectoryResult: MethodChannel.Result? = null
    private var wakeWordDetector: WakeWordDetector? = null
    private var pendingMicIntent = false
    private var pendingNewConvIntent = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TTS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "openSystemTtsSettings" -> {
                    try {
                        startActivity(Intent("com.android.settings.TTS_SETTINGS").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(true)
                    } catch (_: Exception) {
                        try {
                            startActivity(Intent(Settings.ACTION_LOCALE_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                            result.success(true)
                        } catch (_: Exception) {
                            startActivity(Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                            result.success(true)
                        }
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
                "pause" -> {
                    wakeWordDetector?.pause()
                    result.success(true)
                }
                "resume" -> {
                    val threshold = (call.argument<Double>("threshold") ?: 0.5).toFloat()
                    wakeWordDetector?.resume(threshold)
                    result.success(true)
                }
                "setThreshold" -> {
                    result.success(true)
                }
                "setTestMode" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    Log.i("WakeWordDetector", "setTestMode($enabled), detector=$wakeWordDetector, running=${wakeWordDetector?.isRunning}")
                    wakeWordDetector?.sendScoresToDart = enabled
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Share binary messenger with foreground service for Bluetooth MediaSession
        AryaForegroundService.binaryMessenger = flutterEngine.dartExecutor.binaryMessenger

        // Dispatch any pending intents that arrived before the engine was ready
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        if (pendingMicIntent) {
            pendingMicIntent = false
            MethodChannel(messenger, "arya.mic_trigger").invokeMethod("startListening", null)
        }
        if (pendingNewConvIntent) {
            pendingNewConvIntent = false
            MethodChannel(messenger, "arya.mic_trigger").invokeMethod("newConversation", null)
        }
    }

    override fun onStart() {
        super.onStart()
        if (flutterEngine == null) {
            if (hasExtra(intent, "start_mic")) {
                pendingMicIntent = true
            }
            if (hasExtra(intent, "new_conversation")) {
                pendingNewConvIntent = true
            }
        } else {
            handleIntentExtras(intent)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntentExtras(intent)
    }

    private fun hasExtra(intent: Intent?, key: String): Boolean =
        intent?.getBooleanExtra(key, false) == true

    override fun onDestroy() {
        super.onDestroy()
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

    private fun handleIntentExtras(intent: Intent?) {
        val messenger = flutterEngine?.dartExecutor?.binaryMessenger ?: return
        if (intent?.getBooleanExtra("start_mic", false) == true) {
            MethodChannel(messenger, "arya.mic_trigger").invokeMethod("startListening", null)
        }
        if (intent?.getBooleanExtra("new_conversation", false) == true) {
            MethodChannel(messenger, "arya.mic_trigger").invokeMethod("newConversation", null)
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
