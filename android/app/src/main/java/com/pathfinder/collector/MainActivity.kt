package com.pathfinder.collector

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
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
import android.telephony.*
import android.view.View
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
import kotlin.math.*

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
    private lateinit var bottomPanel: View
    private lateinit var toggleHint: TextView

    private val pathPoints = ArrayList<GeoPoint>()
    private var pathOverlay: Polyline? = null
    private val customMarkers = ArrayList<Marker>()

    // Manual speed calculation
    private var lastLocation: Location? = null
    private var lastTime: Long = 0L

    // WiFi scanning
    private lateinit var wifiManager: WifiManager
    private val wifiReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.getBooleanExtra(WifiManager.EXTRA_RESULTS_UPDATED, false)) {
                updateWifiList()
            }
        }
    }
    private lateinit var telephonyManager: TelephonyManager

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Configuration.getInstance().userAgentValue = "PathFinder"

        setContentView(R.layout.activity_main)
        mapView = findViewById(R.id.mapView)
        speedText = findViewById(R.id.speedText)
        wifiListText = findViewById(R.id.wifiListText)
        cellListText = findViewById(R.id.cellListText)
        bottomPanel = findViewById(R.id.bottomPanel)
        toggleHint = findViewById(R.id.toggleHint)

        // ---- Blank canvas (transparent tiles + dark background) ----
        mapView.setBackgroundColor(Color.parseColor("#FF1A1A1A"))
        mapView.setTileSource(object : OnlineTileSourceBase("blank", 0, 20, 256, "", arrayOf("")) {
            override fun getTileURLString(pMapTileIndex: Long): String = ""
            override fun getTileBytes(pMapTileIndex: Long): ByteArray {
                val bmp = Bitmap.createBitmap(256, 256, Bitmap.Config.ARGB_8888)
                bmp.eraseColor(Color.TRANSPARENT)
                val bos = ByteArrayOutputStream()
                bmp.compress(Bitmap.CompressFormat.PNG, 100, bos)
                return bos.toByteArray()
            }
        })
        // Remove any built-in scale bar or grid
        mapView.isTilesScaledToDpi = false
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

        // ---- Toggle bottom panel ----
        toggleHint.setOnClickListener {
            if (bottomPanel.visibility == View.VISIBLE) {
                bottomPanel.visibility = View.GONE
                toggleHint.text = "Tap ▲"
            } else {
                bottomPanel.visibility = View.VISIBLE
                toggleHint.text = "Tap ▼"
            }
        }

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

        // ---- Long-press landmark ----
        val eventsOverlay = MapEventsOverlay(object : MapEventsReceiver {
            override fun singleTapConfirmedHelper(p: GeoPoint): Boolean = false
            override fun longPressHelper(p: GeoPoint): Boolean {
                showAddLandmarkDialog(p)
                return true
            }
        })
        mapView.overlays.add(0, eventsOverlay)

        locationManager = getSystemService(LOCATION_SERVICE) as LocationManager

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
            .setMessage("Your blank map is ready.\nWalk to draw trails.\nLong-press to name places.\nSwipe the bottom panel for WiFi/cell info.")
            .setPositiveButton("Start Mapping") { _, _ -> startAll() }
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
        wifiManager.startScan()
    }

    private val mapLocationListener = LocationListener { location ->
        // Manual speed
        if (lastLocation != null && lastTime != 0L) {
            val distance = lastLocation!!.distanceTo(location)
            val timeDelta = (location.time - lastTime) / 1000.0 // seconds
            if (timeDelta > 0) {
                val speedMs = distance / timeDelta
                val speedKmh = (speedMs * 3.6).toInt()
                speedText.text = "$speedKmh km/h"
            }
        }
        lastLocation = location
        lastTime = location.time

        val newPoint = GeoPoint(location.latitude, location.longitude)
        pathPoints.add(newPoint)
        pathOverlay?.setPoints(pathPoints)
        mapView.invalidate()

        wifiManager.startScan()
        updateCellList()
    }

    private fun updateWifiList() {
        val results: List<ScanResult> = wifiManager.scanResults
        val sb = StringBuilder()
        if (results.isEmpty()) {
            sb.append("No WiFi APs detected")
        } else {
            results.take(5).forEach { ap ->
                sb.append("${ap.SSID ?: "Hidden"} [${ap.level} dBm]\n")
            }
            if (results.size > 5) sb.append("...and ${results.size - 5} more")
        }
        wifiListText.text = sb.toString().trim()
    }

    private fun updateCellList() {
        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE)
            != PackageManager.PERMISSION_GRANTED) {
            cellListText.text = "Cell: permission needed"
            return
        }
        val cells: List<CellInfo> = telephonyManager.allCellInfo
        val sb = StringBuilder()
        if (cells.isEmpty()) {
            sb.append("No cell towers detected (check if phone is connected to mobile network)")
        } else {
            cells.take(3).forEach { cell ->
                when (cell) {
                    is CellInfoLte -> {
                        val id = cell.cellIdentity
                        sb.append("LTE MCC${id.mcc} MNC${id.mnc} TAC${id.tac} CI${id.ci} [${cell.cellSignalStrength.dbm} dBm]\n")
                    }
                    is CellInfoWcdma -> {
                        val id = cell.cellIdentity
                        sb.append("WCDMA MCC${id.mcc} MNC${id.mnc} LAC${id.lac} CID${id.cid} [${cell.cellSignalStrength.dbm} dBm]\n")
                    }
                    is CellInfoGsm -> {
                        val id = cell.cellIdentity
                        sb.append("GSM MCC${id.mcc} MNC${id.mnc} LAC${id.lac} CID${id.cid} [${cell.cellSignalStrength.dbm} dBm]\n")
                    }
                    is CellInfoNr -> {
                        val id = cell.cellIdentity as? CellIdentityNr
                        if (id != null) {
                            sb.append("NR ${id.mccString}/${id.mncString} TAC${id.tac} NCI${id.nci} [${cell.cellSignalStrength.dbm} dBm]\n")
                        }
                    }
                    else -> {}
                }
            }
            if (cells.size > 3) sb.append("...and ${cells.size - 3} more")
        }
        cellListText.text = sb.toString().trim()
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

    // ---------- Permissions (unchanged) ----------
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
