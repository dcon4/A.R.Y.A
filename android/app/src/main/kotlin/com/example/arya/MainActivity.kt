package com.example.arya

import android.content.Intent
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "arya.mic"
    private val SAVE_DIRECTORY_CHANNEL = "arya.save_directory"
    private var saveDirectoryResult: MethodChannel.Result? = null

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
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleMicIntent(intent)
    }

    override fun onStart() {
        super.onStart()
        handleMicIntent(intent)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == PICK_DIRECTORY_REQUEST) {
            if (resultCode == RESULT_OK && data?.data != null) {
                val uri = data.data!!
                // Take persistable permission
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
        // Try to find existing file or create new one
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
