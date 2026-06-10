#!/bin/bash
cd ~/pathfinder-platform

echo "🔧 Fixing strings.xml..."
cat > android/app/src/main/res/values/strings.xml << 'XML'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">PathFinder</string>
</resources>
XML

echo "🗺️  Adding osmdroid dependency to build.gradle.kts..."
# Insert the osmdroid line after the last "implementation" line in dependencies block
sed -i '/implementation("com.google.code.gson:gson:2.11.0")/a\    implementation("org.osmdroid:osmdroid-android:6.1.18")' android/app/build.gradle.kts

echo "🖼️  Creating map layout..."
cat > android/app/src/main/res/layout/activity_main.xml << 'XML'
<?xml version="1.0" encoding="utf-8"?>
<RelativeLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent">

    <org.osmdroid.views.MapView
        android:id="@+id/mapView"
        android:layout_width="match_parent"
        android:layout_height="match_parent" />

</RelativeLayout>
XML

echo "🧠 Replacing MainActivity with map + live trail UI..."
cat > android/app/src/main/java/com/pathfinder/collector/MainActivity.kt << 'KOTLIN'
package com.pathfinder.collector

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.pathfinder.collector.service.CollectorService
import org.osmdroid.config.Configuration
import org.osmdroid.tileprovider.tilesource.TileSourceFactory
import org.osmdroid.util.GeoPoint
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.Polyline
import org.osmdroid.views.overlay.mylocation.GpsMyLocationProvider
import org.osmdroid.views.overlay.mylocation.MyLocationNewOverlay

class MainActivity : AppCompatActivity() {

    companion object {
        private const val PERMISSION_REQUEST_CODE = 1001
    }

    private lateinit var mapView: MapView
    private lateinit var locationManager: LocationManager
    private lateinit var locationOverlay: MyLocationNewOverlay
    private val pathPoints = ArrayList<GeoPoint>()
    private var pathOverlay: Polyline? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // osmdroid needs a user-agent
        Configuration.getInstance().userAgentValue = "PathFinder"

        setContentView(R.layout.activity_main)
        mapView = findViewById(R.id.mapView)
        mapView.setTileSource(TileSourceFactory.MAPNIK)  // OpenStreetMap free tiles
        mapView.setMultiTouchControls(true)

        // Setup location overlay (blue dot)
        locationOverlay = MyLocationNewOverlay(GpsMyLocationProvider(this), mapView)
        locationOverlay.enableMyLocation()
        locationOverlay.enableFollowLocation()
        mapView.overlays.add(locationOverlay)

        // Prepare the path line
        pathOverlay = Polyline().apply {
            color = Color.RED
            width = 8f
        }
        mapView.overlays.add(pathOverlay)

        locationManager = getSystemService(LOCATION_SERVICE) as LocationManager

        if (hasPermissions()) {
            startAll()
        } else {
            requestPermissions()
        }
    }

    private fun startAll() {
        // Start the background collector service (24/7 pinging)
        startCollectorService()

        // Start listening for GPS updates to draw on the map
        if (locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
            try {
                locationManager.requestLocationUpdates(
                    LocationManager.GPS_PROVIDER,
                    5000L,   // every 5 seconds for smooth trail
                    2f,      // at least 2 meters movement
                    mapLocationListener,
                    mainLooper
                )
            } catch (e: SecurityException) {
                // should not happen
            }
        }

        Toast.makeText(this, "PathFinder active. Start walking to build your map.", Toast.LENGTH_LONG).show()
    }

    private val mapLocationListener = LocationListener { location ->
        // Update the map trail
        val newPoint = GeoPoint(location.latitude, location.longitude)
        pathPoints.add(newPoint)
        pathOverlay?.setPoints(pathPoints)
        mapView.invalidate()
    }

    // ---- permission handling same as before ----
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
            startAll()
        }
    }

    private fun startCollectorService() {
        val intent = Intent(this, CollectorService::class.java)
        ContextCompat.startForegroundService(this, intent)
    }

    override fun onResume() {
        super.onResume()
        mapView.onResume()
    }

    override fun onPause() {
        super.onPause()
        mapView.onPause()
    }

    override fun onDestroy() {
        super.onDestroy()
        locationManager.removeUpdates(mapLocationListener)
        mapView.onDetach()
    }
}
KOTLIN

echo "📱 Reminder: Set your server IP in ApiClient.kt before building!"
echo "   Edit: nano android/app/src/main/java/com/pathfinder/collector/network/ApiClient.kt"

