package com.github.gemsnote.model;

import com.raizlabs.android.dbflow.annotation.Column;
import com.raizlabs.android.dbflow.annotation.PrimaryKey;
import com.raizlabs.android.dbflow.annotation.Table;
import com.raizlabs.android.dbflow.structure.BaseModel;

import com.github.gemsnote.database.AppDataBase;

/**
 * Local note content history, mirroring the desktop client behaviour:
 * every time a note is saved, its content is snapshotted locally so
 * previous versions stay available offline.
 */
@Table(name = "NoteHistory", database = AppDataBase.class)
public class NoteHistory extends BaseModel {

    @Column(name = "id")
    @PrimaryKey(autoincrement = true)
    long id;

    @Column(name = "userId")
    String userId = "";

    @Column(name = "noteLocalId")
    long noteLocalId;

    @Column(name = "noteServerId")
    String noteServerId = "";

    @Column(name = "content")
    String content = "";

    @Column(name = "isMarkdown")
    boolean markdown;

    @Column(name = "updatedTime")
    long updatedTime;

    public long getId() {
        return id;
    }

    public void setId(long id) {
        this.id = id;
    }

    public String getUserId() {
        return userId;
    }

    public void setUserId(String userId) {
        this.userId = userId;
    }

    public long getNoteLocalId() {
        return noteLocalId;
    }

    public void setNoteLocalId(long noteLocalId) {
        this.noteLocalId = noteLocalId;
    }

    public String getNoteServerId() {
        return noteServerId;
    }

    public void setNoteServerId(String noteServerId) {
        this.noteServerId = noteServerId;
    }

    public String getContent() {
        return content;
    }

    public void setContent(String content) {
        this.content = content;
    }

    public boolean isMarkdown() {
        return markdown;
    }

    public void setMarkdown(boolean markdown) {
        this.markdown = markdown;
    }

    public long getUpdatedTime() {
        return updatedTime;
    }

    public void setUpdatedTime(long updatedTime) {
        this.updatedTime = updatedTime;
    }
}
