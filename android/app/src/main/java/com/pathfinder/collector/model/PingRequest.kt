package com.pathfinder.collector.model

data class PingRequest(
    val device_id: String,
    val timestamp: String,
    val gps: Map<String, Double>?,
    val wifi: List<WiFiAccessPoint>,
    val cells: List<CellTower>
)
