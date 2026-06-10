package com.pathfinder.collector.network

import com.google.gson.Gson
import com.pathfinder.collector.model.PingRequest
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException

class ApiClient {
    private val client = OkHttpClient()
    private val gson = Gson()
    // TODO: Change this to your server IP before building!
    private val serverUrl = "http://127.0.1.1:8000/api/ping"

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