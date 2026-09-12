package com.github.gemsnote.model;


import com.google.gson.annotations.SerializedName;

public class UpdateRe extends BaseResponse {
    @SerializedName("Usn")
    int usn;

    public int getUsn() {
        return usn;
    }
}
