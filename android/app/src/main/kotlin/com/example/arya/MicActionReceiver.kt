package com.example.arya

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class MicActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (action == "com.example.arya.START_MIC") {
            val launchIntent = Intent(context, MainActivity::class.java).apply {
                putExtra("start_mic", true)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
            context.startActivity(launchIntent)
        }
    }
}
