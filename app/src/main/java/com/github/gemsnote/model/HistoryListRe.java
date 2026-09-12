package com.github.gemsnote.model;

import com.google.gson.annotations.SerializedName;

import java.util.List;

public class HistoryListRe {

    @SerializedName("Ok")
    boolean isOk;
    @SerializedName("Msg")
    String msg;
    @SerializedName("Item")
    List<NoteHistoryMeta> item;

    public boolean isOk() {
        return isOk;
    }

    public String getMsg() {
        return msg;
    }

    public List<NoteHistoryMeta> getItem() {
        return item;
    }
}
