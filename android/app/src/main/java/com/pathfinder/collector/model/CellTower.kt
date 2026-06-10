package com.pathfinder.collector.model

data class CellTower(
    val mcc: Int,
    val mnc: Int,
    val lac: Int,
    val cid: Int,
    val type: String,
    val rssi: Int
)
