package com.pathfinder.collector.receiver

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat
import com.pathfinder.collector.service.CollectorService

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (Intent.ACTION_BOOT_COMPLETED == intent.action) {
            val serviceIntent = Intent(context, CollectorService::class.java)
            ContextCompat.startForegroundService(context, serviceIntent)
        }
    }
}
