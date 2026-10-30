package com.launchvpn.app.pigeon

import kotlinx.serialization.json.Json

object JsonTool {
    val json = Json {
        ignoreUnknownKeys = true
        explicitNulls = false
        encodeDefaults = true
        prettyPrint = true
        prettyPrintIndent = "  "
    }
}
