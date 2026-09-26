package com.github.gemsnote.network.api;

import com.github.gemsnote.model.BaseResponse;
import com.github.gemsnote.model.SyncState;
import com.github.gemsnote.model.User;

import retrofit2.Call;
import retrofit2.http.GET;
import retrofit2.http.POST;
import retrofit2.http.Query;

public interface UserApi {

    @GET("user/info")
    Call<User> getInfo(@Query("userId") String userId);

    @POST("user/updateUsername")
    Call<BaseResponse> updateUsername(@Query("username") String username);

    @POST("user/updatePwd")
    Call<BaseResponse> updatePassword(@Query("oldPwd") String oldPwd, @Query("pwd") String pwd);

    @GET("user/getSyncState")
    Call<SyncState> getSyncState();
}
