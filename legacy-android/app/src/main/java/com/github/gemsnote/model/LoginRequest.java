package com.github.gemsnote.model;

import com.google.gson.annotations.SerializedName;

/** JSON payload used by the versioned API2 authentication endpoints. */
public class LoginRequest {
    @SerializedName("email")
    public final String email;
    @SerializedName("pwd")
    public final String password;

    public LoginRequest(String email, String password) {
        this.email = email;
        this.password = password;
    }
}
