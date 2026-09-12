package com.github.gemsnote.database;

import com.raizlabs.android.dbflow.sql.language.SQLite;

import java.util.List;

import com.github.gemsnote.model.NoteHistory;
import com.github.gemsnote.model.NoteHistory_Table;

public class NoteHistoryDataStore {

    private static final int MAX_HISTORY_PER_NOTE = 20;

    public static List<NoteHistory> getByNoteLocalId(long noteLocalId) {
        return SQLite.select()
                .from(NoteHistory.class)
                .where(NoteHistory_Table.noteLocalId.eq(noteLocalId))
                .orderBy(NoteHistory_Table.updatedTime, false)
                .queryList();
    }

    /**
     * Adds a history snapshot and prunes old ones, keeping at most
     * {@link #MAX_HISTORY_PER_NOTE} entries per note (same as desktop).
     * Consecutive identical contents are skipped.
     */
    public static void addHistory(String userId, long noteLocalId, String noteServerId, String content, boolean markdown, long updatedTime) {
        if (content == null || content.length() == 0) {
            return;
        }
        List<NoteHistory> histories = getByNoteLocalId(noteLocalId);
        if (!histories.isEmpty() && content.equals(histories.get(0).getContent())) {
            return;
        }
        NoteHistory history = new NoteHistory();
        history.setUserId(userId == null ? "" : userId);
        history.setNoteLocalId(noteLocalId);
        history.setNoteServerId(noteServerId == null ? "" : noteServerId);
        history.setContent(content);
        history.setMarkdown(markdown);
        history.setUpdatedTime(updatedTime);
        history.insert();

        for (int i = MAX_HISTORY_PER_NOTE; i < histories.size(); i++) {
            histories.get(i).delete();
        }
    }

    public static void deleteAllByNote(long noteLocalId) {
        SQLite.delete()
                .from(NoteHistory.class)
                .where(NoteHistory_Table.noteLocalId.eq(noteLocalId))
                .execute();
    }

    public static void deleteAllByUserId(String userId) {
        SQLite.delete()
                .from(NoteHistory.class)
                .where(NoteHistory_Table.userId.eq(userId))
                .execute();
    }
}
