#!/bin/bash

# Root Gradle files
cat > android/build.gradle.kts << 'EOF'
plugins {
    id("com.android.application") version "8.2.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.20" apply false
}
EOF

cat > android/settings.gradle.kts << 'EOF'
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "PathFinder"
include(":app")
EOF

cat > android/gradle.properties << 'EOF'
android.useAndroidX=true
kotlin.code.style=official
android.nonTransitiveRClass=true
EOF

# App-level build.gradle.kts
cat > android/app/build.gradle.kts << 'EOF'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.pathfinder.collector"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.pathfinder.collector"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "0.1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.google.code.gson:gson:2.11.0")
}
EOF

# AndroidManifest.xml
cat > android/app/src/main/AndroidManifest.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
    <uses-permission android:name="android.permission.CHANGE_WIFI_STATE" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.READ_PHONE_STATE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />

    <application
        android:allowBackup="true"
        android:supportsRtl="true"
        android:theme="@style/Theme.Material3.DayNight.NoActionBar">

        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>

        <service
            android:name=".service.CollectorService"
            android:foregroundServiceType="location"
            android:exported="false" />

        <receiver
            android:name=".receiver.BootReceiver"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
            </intent-filter>
        </receiver>
    </application>
</manifest>
EOF

# Kotlin sources
PKG="android/app/src/main/java/com/pathfinder/collector"

cat > ${PKG}/MainActivity.kt << 'KOTLIN'
package com.pathfinder.collector

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.pathfinder.collector.service.CollectorService

class MainActivity : AppCompatActivity() {

    companion object {
        private const val PERMISSION_REQUEST_CODE = 1001
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        if (hasPermissions()) {
            startCollectorService()
        } else {
            requestPermissions()
        }
    }

    private fun hasPermissions(): Boolean {
        val location = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION)
        val bgLocation = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_BACKGROUND_LOCATION)
        } else PackageManager.PERMISSION_GRANTED
        val phone = ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE)
        return location == PackageManager.PERMISSION_GRANTED &&
                bgLocation == PackageManager.PERMISSION_GRANTED &&
                phone == PackageManager.PERMISSION_GRANTED
    }

    private fun requestPermissions() {
        val perms = mutableListOf(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.READ_PHONE_STATE
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            perms.add(Manifest.permission.ACCESS_BACKGROUND_LOCATION)
        }
        ActivityCompat.requestPermissions(this, perms.toTypedArray(), PERMISSION_REQUEST_CODE)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST_CODE && hasPermissions()) {
            startCollectorService()
        }
    }

    private fun startCollectorService() {
        val intent = Intent(this, CollectorService::class.java)
        ContextCompat.startForegroundService(this, intent)
    }
}
KOTLIN

cat > ${PKG}/service/CollectorService.kt << 'KOTLIN'
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
                    if (id != null) CellTower(id.mccString.toIntOrNull() ?: 0,
                        id.mncString.toIntOrNull() ?: 0, id.tac, id.nci.toInt(), "NR",
                        cell.cellSignalStrength.dbm) else null
                }
                else -> null
            }
        }

        val gpsMap = gps?.let {
            mapOf("lat" to it.latitude, "lon" to it.longitude, "accuracy" to it.accuracy.toDouble())
        }

        return PingRequest(
            deviceId = Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID),
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
KOTLIN

cat > ${PKG}/model/PingRequest.kt << 'KOTLIN'
package com.pathfinder.collector.model

data class PingRequest(
    val device_id: String,
    val timestamp: String,
    val gps: Map<String, Double>?,
    val wifi: List<WiFiAccessPoint>,
    val cells: List<CellTower>
)
KOTLIN

cat > ${PKG}/model/WiFiAccessPoint.kt << 'KOTLIN'
package com.pathfinder.collector.model

data class WiFiAccessPoint(
    val bssid: String,
    val ssid: String?,
    val rssi: Int
)
KOTLIN

cat > ${PKG}/model/CellTower.kt << 'KOTLIN'
package com.pathfinder.collector.model

data class CellTower(
    val mcc: Int,
    val mnc: Int,
    val lac: Int,
    val cid: Int,
    val type: String,
    val rssi: Int
)
KOTLIN

cat > ${PKG}/network/ApiClient.kt << 'KOTLIN'
package com.pathfinder.collector.network

import com.google.gson.Gson
import com.pathfinder.collector.model.PingRequest
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import java.io.IOException

class ApiClient {
    private val client = OkHttpClient()
    private val gson = Gson()
    // TODO: Change this to your server IP before building!
    private val serverUrl = "http://<your-server-ip>:8000/api/ping"

    fun sendPing(ping: PingRequest) {
        val json = gson.toJson(ping)
        val body = json.toRequestBody("application/json".toMediaType())
        val request = Request.Builder()
            .url(serverUrl)
            .post(body)
            .build()

        client.newCall(request).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) { }
            override fun onResponse(call: Call, response: Response) { response.close() }
        })
    }
}
KOTLIN

cat > ${PKG}/receiver/BootReceiver.kt << 'KOTLIN'
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
KOTLIN

cat > android/app/src/main/res/drawable/ic_notification.xml << 'EOF'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
    <path
        android:fillColor="#FFFFFF"
        android:pathData="M12,2C8.13,2 5,5.13 5,9c0,5.25 7,13 7,13s7,-7.75 7,-13c0,-3.87 -3.13,-7 -7,-7zM12,11.5c-1.38,0 -2.5,-1.12 -2.5,-2.5s1.12,-2.5 2.5,-2.5 2.5,1.12 2.5,2.5 -1.12,2.5 -2.5,2.5z"/>
</vector>
EOF

echo "✅ All PathFinder Android files created successfully!"
echo "Next: edit ApiClient.kt with your server IP, then run ./gradlew assembleDebug"
