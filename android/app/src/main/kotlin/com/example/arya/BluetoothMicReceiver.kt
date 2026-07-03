package com.example.arya

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import android.view.KeyEvent

class BluetoothMicReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "BluetoothMicReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (Intent.ACTION_MEDIA_BUTTON != intent.action) return

        val event = intent.getParcelableExtra<KeyEvent>(Intent.EXTRA_KEY_EVENT) ?: return

        if (event.action == KeyEvent.ACTION_DOWN &&
            event.keyCode == KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
        ) {
            Log.i(TAG, "Bluetooth media button pressed - toggling mic")
            val launchIntent = Intent(context, MainActivity::class.java).apply {
                putExtra("bluetooth_mic_toggle", true)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
            context.startActivity(launchIntent)
            abortBroadcast()
        }
    }
}
