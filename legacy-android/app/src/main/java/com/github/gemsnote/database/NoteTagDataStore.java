package com.github.gemsnote.database;


import com.raizlabs.android.dbflow.sql.language.SQLite;

import com.github.gemsnote.model.RelationshipOfNoteTag;
import com.github.gemsnote.model.RelationshipOfNoteTag_Table;

public class NoteTagDataStore {
    public static void deleteAll(String userId) {
        SQLite.delete()
                .from(RelationshipOfNoteTag.class)
                .where(RelationshipOfNoteTag_Table.userId.eq(userId))
                .execute();
    }
}
