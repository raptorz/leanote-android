package com.github.gemsnote.model;

import com.google.gson.annotations.SerializedName;

public class NoteHistoryMeta {

    @SerializedName("Index")
    int index;
    @SerializedName("HistoryId")
    String historyId = "";
    @SerializedName("UpdatedUserId")
    String updatedUserId = "";
    @SerializedName("UpdatedTime")
    String updatedTimeData = "";
    @SerializedName("Content")
    String content;

    public int getIndex() {
        return index;
    }

    public String getHistoryId() {
        return historyId;
    }

    public String getUpdatedUserId() {
        return updatedUserId;
    }

    public String getUpdatedTimeData() {
        return updatedTimeData;
    }

    public String getContent() {
        return content;
    }
}
