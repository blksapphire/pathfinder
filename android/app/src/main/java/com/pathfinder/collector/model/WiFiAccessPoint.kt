package com.pathfinder.collector.model

data class WiFiAccessPoint(
    val bssid: String,
    val ssid: String?,
    val rssi: Int
)
