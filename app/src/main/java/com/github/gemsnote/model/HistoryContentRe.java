package com.github.gemsnote.model;

import com.google.gson.annotations.SerializedName;

public class HistoryContentRe {

    @SerializedName("Ok")
    boolean isOk;
    @SerializedName("Msg")
    String msg;
    @SerializedName("Item")
    NoteHistoryMeta item;

    public boolean isOk() {
        return isOk;
    }

    public String getMsg() {
        return msg;
    }

    public NoteHistoryMeta getItem() {
        return item;
    }
}
