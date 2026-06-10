package com.pathfinder.collector.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.net.wifi.ScanResult
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.telephony.*
import androidx.core.app.NotificationCompat
import com.google.gson.Gson
import com.pathfinder.collector.MainActivity
import com.pathfinder.collector.R
import com.pathfinder.collector.model.PingRequest
import com.pathfinder.collector.model.WiFiAccessPoint
import com.pathfinder.collector.model.CellTower
import com.pathfinder.collector.network.ApiClient
import java.time.Instant

class CollectorService : Service() {

    private lateinit var locationManager: LocationManager
    private lateinit var wifiManager: WifiManager
    private lateinit var telephonyManager: TelephonyManager
    private var lastGpsLocation: Location? = null
    private val handler = Handler(Looper.getMainLooper())
    private val apiClient = ApiClient()

    companion object {
        const val NOTIFICATION_ID = 1001
        const val CHANNEL_ID = "collector_channel"
        const val GPS_INTERVAL_MS = 10_000L
        const val WIFI_SCAN_INTERVAL_MS = 30_000L
    }

    override fun onCreate() {
        super.onCreate()
        locationManager = getSystemService(LOCATION_SERVICE) as LocationManager
        wifiManager = applicationContext.getSystemService(WIFI_SERVICE) as WifiManager
        telephonyManager = getSystemService(TELEPHONY_SERVICE) as TelephonyManager
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, buildNotification())
        startCollection()
        return START_STICKY
    }

    private fun buildNotification(): Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "PathFinder Tracking",
                NotificationManager.IMPORTANCE_LOW
            )
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(channel)
        }

        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("PathFinder Active")
            .setContentText("Collecting location data")
            .setSmallIcon(R.drawable.ic_notification)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .build()
    }

    private fun startCollection() {
        if (locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
            try {
                locationManager.requestLocationUpdates(
                    LocationManager.GPS_PROVIDER,
                    GPS_INTERVAL_MS,
                    0f,
                    gpsListener,
                    Looper.getMainLooper()
                )
            } catch (e: SecurityException) { }
        }
        handler.post(wifiScanRunnable)
    }

    private val gpsListener = LocationListener { location ->
        lastGpsLocation = location
    }

    private val wifiScanRunnable = object : Runnable {
        override fun run() {
            wifiManager.startScan()
            handler.postDelayed({
                collectAndSend()
                handler.postDelayed(this, WIFI_SCAN_INTERVAL_MS)
            }, 2000)
        }
    }

    private fun collectAndSend() {
        val wifiResults = wifiManager.scanResults
        val cellInfos = telephonyManager.allCellInfo
        val gps = lastGpsLocation
        val ping = buildPing(gps, wifiResults, cellInfos)
        apiClient.sendPing(ping)
    }

    private fun buildPing(gps: Location?, wifi: List<ScanResult>, cells: List<CellInfo>): PingRequest {
        val wifiList = wifi.map {
            WiFiAccessPoint(bssid = it.BSSID, ssid = it.SSID, rssi = it.level)
        }
        val cellList = cells.mapNotNull { cell ->
            when (cell) {
                is CellInfoLte -> {
                    val id = cell.cellIdentity
                    CellTower(id.mcc, id.mnc, id.tac, id.ci, "LTE", cell.cellSignalStrength.dbm)
                }
                is CellInfoWcdma -> {
                    val id = cell.cellIdentity
                    CellTower(id.mcc, id.mnc, id.lac, id.cid, "WCDMA", cell.cellSignalStrength.dbm)
                }
                is CellInfoGsm -> {
                    val id = cell.cellIdentity
                    CellTower(id.mcc, id.mnc, id.lac, id.cid, "GSM", cell.cellSignalStrength.dbm)
                }
                is CellInfoNr -> {
                    val id = cell.cellIdentity as? CellIdentityNr
                    if (id != null) CellTower(
                        id.mccString?.toIntOrNull() ?: 0,
                        id.mncString?.toIntOrNull() ?: 0,
                        id.tac,
                        id.nci.toInt(),
                        "NR",
                        cell.cellSignalStrength.dbm
                    ) else null
                }
                else -> null
            }
        }

        val gpsMap = gps?.let {
            mapOf("lat" to it.latitude, "lon" to it.longitude, "accuracy" to it.accuracy.toDouble())
        }

        return PingRequest(
            device_id = Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID),
            timestamp = Instant.now().toString(),
            gps = gpsMap,
            wifi = wifiList,
            cells = cellList
        )
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        locationManager.removeUpdates(gpsListener)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}