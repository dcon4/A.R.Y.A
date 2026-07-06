package com.example.arya

import android.app.Notification
import android.app.Notification.MediaStyle
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import android.view.KeyEvent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class AryaForegroundService : Service() {
    companion object {
        private const val CHANNEL_ID = "arya_foreground_v2"
        private const val NOTIFICATION_ID = 1001
        private const val ACTION_START = "com.example.arya.START_FOREGROUND"
        private const val ACTION_STOP = "com.example.arya.STOP_FOREGROUND"
        const val ACTION_START_MIC = "com.example.arya.START_MIC"
        const val ACTION_TOGGLE_BRAVE_SEARCH = "com.example.arya.TOGGLE_BRAVE_SEARCH"
        const val ACTION_ROTATE_PROVIDER = "com.example.arya.ROTATE_PROVIDER"
        const val ACTION_ROTATE_ANNOUNCE_MODE = "com.example.arya.ROTATE_ANNOUNCE_MODE"
        var binaryMessenger: BinaryMessenger? = null

        fun start(context: Context) {
            val intent = Intent(context, AryaForegroundService::class.java).apply {
                action = ACTION_START
            }
            context.startForegroundService(intent)
        }

        fun stop(context: Context) {
            val intent = Intent(context, AryaForegroundService::class.java).apply {
                action = ACTION_STOP
            }
            context.startService(intent)
        }

        fun startMic(context: Context) {
            val intent = Intent(context, AryaForegroundService::class.java).apply {
                action = ACTION_START_MIC
            }
            context.startService(intent)
        }
    }

    private var mediaSession: MediaSession? = null
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        setupMediaSession()
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "arya:wake_lock")
        wakeLock?.acquire()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
            ACTION_START_MIC -> {
                binaryMessenger?.let { messenger ->
                    MethodChannel(messenger, "arya.mic_trigger").invokeMethod("startListening", null)
                } ?: triggerMic()
            }
            "com.example.arya.NEW_CONVERSATION" -> {
                triggerNewConversation()
            }
            ACTION_TOGGLE_BRAVE_SEARCH -> {
                binaryMessenger?.let { messenger ->
                    MethodChannel(messenger, "arya.mic_trigger").invokeMethod("toggleBraveSearch", null)
                }
            }
            ACTION_ROTATE_PROVIDER -> {
                binaryMessenger?.let { messenger ->
                    MethodChannel(messenger, "arya.mic_trigger").invokeMethod("rotateProvider", null)
                }
            }
            ACTION_ROTATE_ANNOUNCE_MODE -> {
                binaryMessenger?.let { messenger ->
                    MethodChannel(messenger, "arya.mic_trigger").invokeMethod("rotateAnnounceMode", null)
                }
            }
            // ACTION_START, null intent (START_STICKY restart), or unknown action
            else -> {
                val notification = buildNotification()
                startForeground(NOTIFICATION_ID, notification)
            }
        }
        return START_STICKY
    }

    private fun setupMediaSession() {
        mediaSession = MediaSession(this, "arya_foreground_bluetooth")
        mediaSession?.let { session ->
            session.setCallback(object : MediaSession.Callback() {
                override fun onMediaButtonEvent(mediaButtonIntent: Intent): Boolean {
                    val event = mediaButtonIntent.getParcelableExtra<KeyEvent>(Intent.EXTRA_KEY_EVENT)
                    if (event?.action == KeyEvent.ACTION_DOWN &&
                        event.keyCode == KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
                    ) {
                        Log.i("AryaForegroundService", "Bluetooth media button pressed via MediaSession")
                        val prefs = applicationContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                        val enabled = prefs.getBoolean("bluetooth_mic_control", false)
                        if (enabled) {
                            binaryMessenger?.let { messenger ->
                                MethodChannel(messenger, "arya.bluetooth_mic_toggle").invokeMethod("toggleMic", null)
                            } ?: run {
                                triggerMic()
                            }
                        }
                        return true
                    }
                    return super.onMediaButtonEvent(mediaButtonIntent)
                }
            })
            session.setPlaybackState(
                PlaybackState.Builder()
                    .setActions(PlaybackState.ACTION_PLAY_PAUSE)
                    .setState(PlaybackState.STATE_NONE, PlaybackState.PLAYBACK_POSITION_UNKNOWN, 0f)
                    .build()
            )
            session.setFlags(MediaSession.FLAG_HANDLES_MEDIA_BUTTONS or MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS)
            session.isActive = true
        }
    }

    fun triggerNewConversation() {
        binaryMessenger?.let { messenger ->
            MethodChannel(messenger, "arya.mic_trigger").invokeMethod("newConversation", null)
        }
    }

    private fun triggerMic() {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            putExtra("start_mic", true)
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(launchIntent)
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "ARYA Background Service",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "ARYA background service for Bluetooth and wake word"
            setShowBadge(false)
        }
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val micIntent = Intent(this, AryaForegroundService::class.java).apply {
            action = ACTION_START_MIC
        }
        val micPendingIntent = PendingIntent.getService(
            this,
            0,
            micIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val newConvIntent = Intent(this, MainActivity::class.java).apply {
            putExtra("new_conversation", true)
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val newConvPendingIntent = PendingIntent.getActivity(
            this,
            3,
            newConvIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val toggleBraveIntent = Intent(this, AryaForegroundService::class.java).apply {
            action = ACTION_TOGGLE_BRAVE_SEARCH
        }
        val toggleBravePendingIntent = PendingIntent.getService(
            this,
            4,
            toggleBraveIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val rotateProviderIntent = Intent(this, AryaForegroundService::class.java).apply {
            action = ACTION_ROTATE_PROVIDER
        }
        val rotateProviderPendingIntent = PendingIntent.getService(
            this,
            5,
            rotateProviderIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val rotateAnnounceIntent = Intent(this, AryaForegroundService::class.java).apply {
            action = ACTION_ROTATE_ANNOUNCE_MODE
        }
        val rotateAnnouncePendingIntent = PendingIntent.getService(
            this,
            6,
            rotateAnnounceIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val openIntent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val openPendingIntent = PendingIntent.getActivity(
            this,
            1,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val sessionToken = mediaSession?.sessionToken

        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("ARYA")
            .setContentText("Start Mic, New Conversation, or change settings.")
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_TRANSPORT)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setContentIntent(openPendingIntent)
            .setStyle(MediaStyle().setMediaSession(sessionToken))
            .addAction(
                R.drawable.ic_launcher_foreground,
                "Start Mic",
                micPendingIntent
            )
            .addAction(
                R.drawable.ic_launcher_foreground,
                "New Conversation",
                newConvPendingIntent
            )
            .addAction(
                R.drawable.ic_launcher_foreground,
                "Announce Mode",
                rotateAnnouncePendingIntent
            )
            .addAction(
                R.drawable.ic_launcher_foreground,
                "Rotate Provider",
                rotateProviderPendingIntent
            )
            .addAction(
                R.drawable.ic_launcher_foreground,
                "Brave Search",
                toggleBravePendingIntent
            )
            .build()
    }

    override fun onDestroy() {
        super.onDestroy()
        mediaSession?.isActive = false
        mediaSession?.release()
        mediaSession = null
        wakeLock?.release()
        wakeLock = null
    }
}
