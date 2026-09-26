package com.github.gemsnote.model;

import com.google.gson.annotations.SerializedName;

/** Public server metadata returned by GET /api2/system/version. */
public class ServerVersion {
    @SerializedName("server")
    private String server = "";
    @SerializedName("version")
    private String version = "";
    @SerializedName("min_version")
    private String minimumVersion = "";

    public String getServer() {
        return server;
    }

    public String getVersion() {
        return version;
    }

    public String getMinimumVersion() {
        return minimumVersion;
    }

    public boolean isGemsnote() {
        return "gemsnote".equalsIgnoreCase(server);
    }
}
