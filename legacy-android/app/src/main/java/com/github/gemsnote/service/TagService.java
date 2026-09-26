package com.github.gemsnote.service;

import android.text.TextUtils;

import com.elvishew.xlog.XLog;

import java.util.List;

import com.github.gemsnote.model.Account;
import com.github.gemsnote.model.Tag;
import com.github.gemsnote.network.ApiProvider;
import com.github.gemsnote.utils.RetrofitUtils;

/**
 * Tag management: incremental tag sync with the server plus
 * standalone tag add/delete (desktop parity).
 */
public class TagService {

    private static final String TAG = "TagService:";
    private static final int MAX_ENTRY = 100;

    public static void syncTagsFromServer() {
        Account account = Account.getCurrent();
        if (account == null) {
            return;
        }
        int tagUsn = account.getTagUsn();
        List<Tag> tags;
        do {
            tags = RetrofitUtils.excuteWithException(
                    ApiProvider.getInstance().getTagApi().getSyncTags(tagUsn, MAX_ENTRY));
            for (Tag remoteTag : tags) {
                Tag localTag = null;
                if (!TextUtils.isEmpty(remoteTag.getTagId())) {
                    localTag = Tag.getByTagId(remoteTag.getTagId(), account.getUserId());
                }
                if (localTag == null) {
                    localTag = Tag.getByText(remoteTag.getText(), account.getUserId());
                }
                if (remoteTag.isDeleted()) {
                    if (localTag != null) {
                        XLog.i(TAG + "tag deleted on server, text=" + localTag.getText());
                        Tag.deleteTagAndRelations(localTag);
                    }
                } else if (localTag == null) {
                    remoteTag.setUserId(account.getUserId());
                    remoteTag.insert();
                    XLog.i(TAG + "tag insert, usn=" + remoteTag.getUsn() + ", text=" + remoteTag.getText());
                } else {
                    remoteTag.setId(localTag.getId());
                    remoteTag.update();
                    XLog.i(TAG + "tag update, usn=" + remoteTag.getUsn() + ", text=" + remoteTag.getText());
                }
                tagUsn = remoteTag.getUsn();
                account.setTagUsn(tagUsn);
                account.save();
            }
        } while (tags.size() == MAX_ENTRY);
    }

    public static Tag addTag(String text) {
        Tag tag = RetrofitUtils.excuteWithException(ApiProvider.getInstance().getTagApi().addTag(text));
        if (tag == null || TextUtils.isEmpty(tag.getText())) {
            throw new IllegalStateException("Add tag failed");
        }
        Account account = Account.getCurrent();
        Tag localTag = Tag.getByText(tag.getText(), account.getUserId());
        if (localTag == null) {
            tag.setUserId(account.getUserId());
            tag.insert();
        } else {
            tag.setId(localTag.getId());
            tag.update();
        }
        updateTagUsnIfNeed(tag.getUsn());
        return tag;
    }

    public static void deleteTag(Tag tag) {
        if (!TextUtils.isEmpty(tag.getTagId()) || tag.getUsn() > 0) {
            RetrofitUtils.excuteWithException(
                    ApiProvider.getInstance().getTagApi().deleteTag(tag.getText(), tag.getUsn()));
        }
        Tag.deleteTagAndRelations(tag);
        updateTagUsnIfNeed(tag.getUsn());
    }

    /**
     * if new usn equals to (current usn + 1), then just simply update usn without syncing.
     */
    private static void updateTagUsnIfNeed(int newUsn) {
        Account account = Account.getCurrent();
        if (newUsn - account.getTagUsn() == 1) {
            account.setTagUsn(newUsn);
            account.update();
        }
    }
}
