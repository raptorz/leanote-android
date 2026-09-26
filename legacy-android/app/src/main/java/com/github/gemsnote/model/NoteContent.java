package com.github.gemsnote.model;

import com.google.gson.annotations.SerializedName;

/** Body returned by API2 GET /note/getNoteContent. */
public class NoteContent extends BaseResponse {
    @SerializedName("NoteId")
    private String noteId = "";
    @SerializedName("UserId")
    private String userId = "";
    @SerializedName("Content")
    private String content = "";

    public String getNoteId() {
        return noteId;
    }

    public String getUserId() {
        return userId;
    }

    public String getContent() {
        return content;
    }
}
