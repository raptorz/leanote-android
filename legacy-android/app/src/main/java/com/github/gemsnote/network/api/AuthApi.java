package com.github.gemsnote.network.api;

import com.github.gemsnote.model.Authentication;
import com.github.gemsnote.model.BaseResponse;
import com.github.gemsnote.model.LoginRequest;

import retrofit2.Call;
import retrofit2.http.Body;
import retrofit2.http.POST;

public interface AuthApi {

    @POST("auth/login")
    Call<Authentication> login(@Body LoginRequest request);

    @POST("auth/logout")
    Call<BaseResponse> logout();

    @POST("auth/register")
    Call<BaseResponse> register(@Body LoginRequest request);
}
