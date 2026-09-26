package com.github.gemsnote.network.api;

import com.github.gemsnote.model.ServerVersion;

import retrofit2.Call;
import retrofit2.http.GET;

public interface SystemApi {
    @GET("system/version")
    Call<ServerVersion> getVersion();
}
