package com.example.arya

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.IBinder
import android.util.Log
import android.view.KeyEvent
import androidx.core.app.NotificationCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class AryaForegroundService : Service() {
    companion object {
        private const val CHANNEL_ID = "arya_foreground_v2"
        private const val NOTIFICATION_ID = 1001
        private const val ACTION_START = "com.example.arya.START_FOREGROUND"
        private const val ACTION_STOP = "com.example.arya.STOP_FOREGROUND"
        const val ACTION_START_MIC = "com.example.arya.START_MIC"
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

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        setupMediaSession()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val notification = buildNotification()
                startForeground(NOTIFICATION_ID, notification)
            }
            ACTION_STOP -> {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
            ACTION_START_MIC -> {
                triggerMic()
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

    private fun triggerMic() {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            putExtra("start_mic", true)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        startActivity(launchIntent)
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "ARYA Background Service",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Keeps ARYA running in the background and listens for Bluetooth media buttons."
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

        val openIntent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val openPendingIntent = PendingIntent.getActivity(
            this,
            1,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("ARYA")
            .setContentText("Bluetooth: press play/pause or Start Mic.")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setContentIntent(openPendingIntent)
            .addAction(
                android.R.drawable.ic_btn_speak_now,
                "Start Mic",
                micPendingIntent
            )
            .build()
    }

    override fun onDestroy() {
        super.onDestroy()
        mediaSession?.isActive = false
        mediaSession?.release()
        mediaSession = null
    }
}
