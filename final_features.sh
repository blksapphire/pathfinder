#!/bin/bash
cd ~/pathfinder-platform

echo "🌙 Applying dark theme, WiFi/cell radar, white trail, and app name fix..."

# ---- 1. Dark theme styles ----
mkdir -p android/app/src/main/res/values
cat > android/app/src/main/res/values/themes.xml << 'XML'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="Theme.PathFinder" parent="Theme.Material3.Dark.NoActionBar">
        <item name="colorPrimary">#FFBB86FC</item>
        <item name="colorOnPrimary">#FF000000</item>
        <item name="colorSecondary">#FF03DAC6</item>
        <item name="colorOnSecondary">#FF000000</item>
        <item name="android:statusBarColor">@android:color/black</item>
        <item name="android:navigationBarColor">@android:color/black</item>
    </style>
</resources>
XML

# ---- 2. Fix strings.xml (app name) ----
cat > android/app/src/main/res/values/strings.xml << 'XML'
<resources>
    <string name="app_name">PathFinder</string>
</resources>
XML

# ---- 3. Manifest: set theme and label ----
cat > android/app/src/main/AndroidManifest.xml << 'XML'
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
        android:label="@string/app_name"
        android:theme="@style/Theme.PathFinder">

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
XML

# ---- 4. Updated layout with WiFi/cell panel ----
cat > android/app/src/main/res/layout/activity_main.xml << 'XML'
<?xml version="1.0" encoding="utf-8"?>
<RelativeLayout xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="@android:color/black">

    <org.osmdroid.views.MapView
        android:id="@+id/mapView"
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:layout_above="@+id/bottomPanel" />

    <!-- Speed display -->
    <TextView
        android:id="@+id/speedText"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_alignParentStart="true"
        android:layout_alignParentTop="true"
        android:layout_margin="12dp"
        android:background="#CC333333"
        android:padding="8dp"
        android:text="0 km/h"
        android:textColor="#FFFFFF"
        android:textSize="18sp" />

    <!-- Info / About button -->
    <com.google.android.material.floatingactionbutton.FloatingActionButton
        android:id="@+id/fabInfo"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_alignParentEnd="true"
        android:layout_above="@+id/bottomPanel"
        android:layout_margin="16dp"
        android:contentDescription="About"
        app:srcCompat="@android:drawable/ic_dialog_info"
        app:backgroundTint="#FFBB86FC" />

    <!-- Bottom panel for WiFi & cell data -->
    <LinearLayout
        android:id="@+id/bottomPanel"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_alignParentBottom="true"
        android:orientation="vertical"
        android:background="#CC222222"
        android:padding="8dp">

        <TextView
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:text="Nearby signals"
            android:textColor="#FFBB86FC"
            android:textSize="14sp"
            android:textStyle="bold" />

        <TextView
            android:id="@+id/wifiListText"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:text="WiFi: scanning..."
            android:textColor="#CCCCCC"
            android:textSize="12sp"
            android:maxLines="5"
            android:ellipsize="end" />

        <TextView
            android:id="@+id/cellListText"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:text="Cell: scanning..."
            android:textColor="#CCCCCC"
            android:textSize="12sp"
            android:maxLines="3"
            android:ellipsize="end" />
    </LinearLayout>

</RelativeLayout>
XML

# ---- 5. MainActivity with WiFi/cell scanning, white trail, dark theme support ----
cat > android/app/src/main/java/com/pathfinder/collector/MainActivity.kt << 'KOTLIN'
package com.pathfinder.collector

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.DialogInterface
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Color
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.net.wifi.ScanResult
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import android.telephony.CellInfo
import android.telephony.CellInfoGsm
import android.telephony.CellInfoLte
import android.telephony.CellInfoNr
import android.telephony.CellInfoWcdma
import android.telephony.CellIdentityNr
import android.telephony.TelephonyManager
import android.widget.EditText
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.pathfinder.collector.service.CollectorService
import org.osmdroid.config.Configuration
import org.osmdroid.events.MapEventsReceiver
import org.osmdroid.tileprovider.tilesource.OnlineTileSourceBase
import org.osmdroid.util.GeoPoint
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.MapEventsOverlay
import org.osmdroid.views.overlay.Marker
import org.osmdroid.views.overlay.Polyline
import org.osmdroid.views.overlay.mylocation.GpsMyLocationProvider
import org.osmdroid.views.overlay.mylocation.MyLocationNewOverlay
import java.io.ByteArrayOutputStream
import java.util.Locale

class MainActivity : AppCompatActivity() {

    companion object {
        private const val PERMISSION_REQUEST_CODE = 1001
    }

    private lateinit var mapView: MapView
    private lateinit var locationManager: LocationManager
    private lateinit var locationOverlay: MyLocationNewOverlay
    private lateinit var speedText: TextView
    private lateinit var wifiListText: TextView
    private lateinit var cellListText: TextView
    private val pathPoints = ArrayList<GeoPoint>()
    private var pathOverlay: Polyline? = null
    private val customMarkers = ArrayList<Marker>()

    // WiFi scanning
    private lateinit var wifiManager: WifiManager
    private val wifiReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.getBooleanExtra(WifiManager.EXTRA_RESULTS_UPDATED, false)) {
                updateWifiList()
            }
        }
    }

    // Cell info
    private lateinit var telephonyManager: TelephonyManager

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        Configuration.getInstance().userAgentValue = "PathFinder"

        setContentView(R.layout.activity_main)
        mapView = findViewById(R.id.mapView)
        speedText = findViewById(R.id.speedText)
        wifiListText = findViewById(R.id.wifiListText)
        cellListText = findViewById(R.id.cellListText)

        // ---- Dark background (no tiles) ----
        mapView.setBackgroundColor(Color.parseColor("#FF1E1E1E"))
        mapView.setTileSource(object : OnlineTileSourceBase("blank", 0, 20, 256, "", arrayOf("")) {
            override fun getTileURLString(pMapTileIndex: Long): String = ""
            override fun getTileLocalFile(pMapTileIndex: Long): String? = null
            override fun getTileBytes(pMapTileIndex: Long): ByteArray {
                val bmp = Bitmap.createBitmap(256, 256, Bitmap.Config.ARGB_8888)
                bmp.eraseColor(Color.TRANSPARENT)
                val bos = ByteArrayOutputStream()
                bmp.compress(Bitmap.CompressFormat.PNG, 100, bos)
                return bos.toByteArray()
            }
        })
        mapView.setMultiTouchControls(true)
        mapView.controller.setZoom(18.0)
        mapView.controller.setCenter(GeoPoint(0.0, 0.0))

        // ---- Location overlay (blue dot) ----
        locationOverlay = MyLocationNewOverlay(GpsMyLocationProvider(this), mapView)
        locationOverlay.enableMyLocation()
        locationOverlay.enableFollowLocation()
        mapView.overlays.add(locationOverlay)

        // ---- White trail ----
        pathOverlay = Polyline().apply {
            outlinePaint.color = Color.WHITE
            outlinePaint.strokeWidth = 8f
        }
        mapView.overlays.add(pathOverlay)

        // ---- WiFi & cell managers ----
        wifiManager = applicationContext.getSystemService(WIFI_SERVICE) as WifiManager
        telephonyManager = getSystemService(TELEPHONY_SERVICE) as TelephonyManager

        // ---- About button ----
        val fabInfo = findViewById<com.google.android.material.floatingactionbutton.FloatingActionButton>(R.id.fabInfo)
        fabInfo.setOnClickListener {
            AlertDialog.Builder(this)
                .setTitle("About PathFinder")
                .setMessage("PathFinder v0.1.0\n\n" +
                        "Your private location platform.\n" +
                        "Map built by walking.\n\n" +
                        "Developer: [Your Name / Startup]\n" +
                        "No external map data used.")
                .setPositiveButton("OK", null)
                .show()
        }

        // ---- Long-press to add landmark ----
        val eventsOverlay = MapEventsOverlay(object : MapEventsReceiver {
            override fun singleTapConfirmedHelper(p: GeoPoint): Boolean = false
            override fun longPressHelper(p: GeoPoint): Boolean {
                showAddLandmarkDialog(p)
                return true
            }
        })
        mapView.overlays.add(0, eventsOverlay)

        locationManager = getSystemService(LOCATION_SERVICE) as LocationManager

        // Register WiFi scan results receiver
        val intentFilter = IntentFilter(WifiManager.SCAN_RESULTS_AVAILABLE_ACTION)
        registerReceiver(wifiReceiver, intentFilter)

        if (hasPermissions()) {
            showWelcomeDialog()
        } else {
            requestPermissions()
        }
    }

    private fun showWelcomeDialog() {
        AlertDialog.Builder(this)
            .setTitle("Welcome to PathFinder")
            .setMessage("This is your own blank map. Walk to draw trails.\n" +
                    "Long-press to name buildings and landmarks.\n" +
                    "Bottom panel shows nearby WiFi & cell towers.\n" +
                    "Your map is built entirely by you.")
            .setPositiveButton("Start Mapping") { _, _ ->
                startAll()
            }
            .setCancelable(false)
            .show()
    }

    private fun startAll() {
        startCollectorService()

        if (locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
            try {
                locationManager.requestLocationUpdates(
                    LocationManager.GPS_PROVIDER,
                    5000L,
                    2f,
                    mapLocationListener,
                    mainLooper
                )
            } catch (e: SecurityException) { }
        }

        // Trigger first scan
        wifiManager.startScan()
    }

    private val mapLocationListener = LocationListener { location ->
        val newPoint = GeoPoint(location.latitude, location.longitude)
        pathPoints.add(newPoint)
        pathOverlay?.setPoints(pathPoints)
        mapView.invalidate()

        val speedKmh = if (location.hasSpeed()) (location.speed * 3.6f).toInt() else 0
        speedText.text = String.format(Locale.getDefault(), "%d km/h", speedKmh)

        // Request a WiFi scan with each GPS update (throttled by OS)
        wifiManager.startScan()
        // Update cell list immediately
        updateCellList()
    }

    private fun updateWifiList() {
        val results: List<ScanResult> = wifiManager.scanResults
        val sb = StringBuilder("WiFi: ")
        if (results.isEmpty()) {
            sb.append("none")
        } else {
            results.take(5).forEach { ap ->
                sb.append("${ap.SSID ?: "?"} (${ap.level} dBm), ")
            }
            if (results.size > 5) sb.append("+${results.size - 5} more")
        }
        wifiListText.text = sb.toString().trimEnd(',')
    }

    private fun updateCellList() {
        val cells: List<CellInfo> = telephonyManager.allCellInfo
        val sb = StringBuilder("Cell: ")
        if (cells.isEmpty()) {
            sb.append("none")
        } else {
            cells.take(3).forEach { cell ->
                when (cell) {
                    is CellInfoLte -> {
                        val id = cell.cellIdentity
                        sb.append("LTE ${id.mcc}/${id.mnc} TAC=${id.tac} CI=${id.ci} (${cell.cellSignalStrength.dbm} dBm), ")
                    }
                    is CellInfoWcdma -> {
                        val id = cell.cellIdentity
                        sb.append("WCDMA ${id.mcc}/${id.mnc} LAC=${id.lac} CID=${id.cid} (${cell.cellSignalStrength.dbm} dBm), ")
                    }
                    is CellInfoGsm -> {
                        val id = cell.cellIdentity
                        sb.append("GSM ${id.mcc}/${id.mnc} LAC=${id.lac} CID=${id.cid} (${cell.cellSignalStrength.dbm} dBm), ")
                    }
                    is CellInfoNr -> {
                        val id = cell.cellIdentity as? CellIdentityNr
                        if (id != null) {
                            sb.append("NR ${id.mccString}/${id.mncString} TAC=${id.tac} NCI=${id.nci} (${cell.cellSignalStrength.dbm} dBm), ")
                        }
                    }
                    else -> {}
                }
            }
            if (cells.size > 3) sb.append("+${cells.size - 3} more")
        }
        cellListText.text = sb.toString().trimEnd(',')
    }

    // ---------- Landmark dialog (unchanged) ----------
    private fun showAddLandmarkDialog(p: GeoPoint) {
        val input = EditText(this)
        input.hint = "Name (e.g. Main Street, Office Building)"
        AlertDialog.Builder(this)
            .setTitle("Add Landmark")
            .setView(input)
            .setPositiveButton("Save") { _, _ ->
                val name = input.text.toString().trim()
                if (name.isNotEmpty()) {
                    addLandmark(p, name)
                }
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun addLandmark(point: GeoPoint, name: String) {
        val marker = Marker(mapView).apply {
            position = point
            setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_BOTTOM)
            title = name
            snippet = "Added by you"
            setInfoWindow(null)
        }
        mapView.overlays.add(marker)
        customMarkers.add(marker)
        mapView.invalidate()
        Toast.makeText(this, "Added: $name", Toast.LENGTH_SHORT).show()
    }

    // ---------- Permissions ----------
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
            showWelcomeDialog()
        } else {
            Toast.makeText(this, "Permissions needed to continue", Toast.LENGTH_LONG).show()
        }
    }

    private fun startCollectorService() {
        val intent = Intent(this, CollectorService::class.java)
        ContextCompat.startForegroundService(this, intent)
    }

    override fun onResume() {
        super.onResume()
        mapView.onResume()
        registerReceiver(wifiReceiver, IntentFilter(WifiManager.SCAN_RESULTS_AVAILABLE_ACTION))
    }

    override fun onPause() {
        super.onPause()
        mapView.onPause()
        try { unregisterReceiver(wifiReceiver) } catch (e: Exception) {}
    }

    override fun onDestroy() {
        super.onDestroy()
        locationManager.removeUpdates(mapLocationListener)
        mapView.onDetach()
        try { unregisterReceiver(wifiReceiver) } catch (e: Exception) {}
    }
}
KOTLIN

echo "✅ All features added. Rebuilding..."
cd android
./gradlew clean assembleDebug
