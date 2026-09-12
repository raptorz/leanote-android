package com.github.gemsnote.network.api;

import com.github.gemsnote.model.BaseResponse;
import com.github.gemsnote.model.Tag;

import java.util.List;

import retrofit2.Call;
import retrofit2.http.GET;
import retrofit2.http.POST;
import retrofit2.http.Query;

public interface TagApi {

    @GET("tag/getSyncTags")
    Call<List<Tag>> getSyncTags(@Query("afterUsn") int afterUsn, @Query("maxEntry") int maxEntry);

    @POST("tag/addTag")
    Call<Tag> addTag(@Query("tag") String tag);

    @POST("tag/deleteTag")
    Call<BaseResponse> deleteTag(@Query("tag") String tag, @Query("usn") int usn);
}
