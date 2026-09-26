package com.github.gemsnote.ui;

import android.app.AlertDialog;
import android.content.Context;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.pm.ActivityInfo;
import android.graphics.Typeface;
import android.net.Uri;
import android.os.Bundle;
import androidx.appcompat.widget.Toolbar;
import android.text.TextUtils;
import android.view.Menu;
import android.view.MenuItem;
import android.view.View;
import android.widget.ScrollView;
import android.widget.TextView;

import com.elvishew.xlog.XLog;

import com.github.gemsnote.BuildConfig;
import com.github.gemsnote.R;
import com.github.gemsnote.database.NoteDataStore;
import com.github.gemsnote.database.NoteHistoryDataStore;
import com.github.gemsnote.model.HistoryContentRe;
import com.github.gemsnote.model.HistoryListRe;
import com.github.gemsnote.model.Note;
import com.github.gemsnote.model.NoteFile;
import com.github.gemsnote.model.NoteHistory;
import com.github.gemsnote.model.NoteHistoryMeta;
import com.github.gemsnote.network.ApiProvider;
import com.github.gemsnote.service.NoteFileService;
import com.github.gemsnote.service.NoteService;
import com.github.gemsnote.ui.edit.EditorFragment;
import com.github.gemsnote.ui.edit.NoteEditActivity;
import com.github.gemsnote.utils.DialogDisplayer;
import com.github.gemsnote.utils.NetworkUtils;
import com.github.gemsnote.utils.OpenUtils;
import com.github.gemsnote.utils.RetrofitUtils;
import com.github.gemsnote.utils.TimeUtils;
import com.github.gemsnote.utils.ToastUtils;

import butterknife.BindView;
import butterknife.ButterKnife;
import butterknife.OnClick;
import rx.Observable;
import rx.Observer;
import rx.Subscriber;
import rx.android.schedulers.AndroidSchedulers;
import rx.functions.Action0;
import rx.functions.Action1;
import rx.schedulers.Schedulers;

import static android.content.res.Configuration.ORIENTATION_PORTRAIT;

import java.io.File;
import java.io.IOException;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Locale;

public class NotePreviewActivity extends BaseActivity implements EditorFragment.EditorFragmentListener {

    private static final String TAG = "NotePreviewActivity:";
    public static final String EXT_NOTE_LOCAL_ID = "ext_note_local_id";
    public static final int REQ_EDIT = 1;

    private EditorFragment mEditorFragment;
    private Note mNote;

    @BindView(R.id.rl_action)
    View mActionContainer;
    @BindView(R.id.tv_revert)
    View mRevertBtn;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_preview);
        ButterKnife.bind(this);
        initToolBar((Toolbar) findViewById(R.id.toolbar), true);
        long noteLocalId = getIntent().getLongExtra(EXT_NOTE_LOCAL_ID, -1);
        mNote = NoteDataStore.getByLocalId(noteLocalId);
        if (mNote == null) {
            ToastUtils.show(this, R.string.note_not_found);
            finish();
            return;
        }
        mEditorFragment = EditorFragment.getNewInstance(mNote.isMarkDown(), false);
        getSupportFragmentManager().beginTransaction().add(R.id.container, mEditorFragment).commit();
    }

    public static Intent getOpenIntent(Context context, long noteLocalId) {
        Intent intent = new Intent(context, NotePreviewActivity.class);
        intent.putExtra(EXT_NOTE_LOCAL_ID, noteLocalId);
        return intent;
    }

    @Override
    public boolean onCreateOptionsMenu(Menu menu) {
        getMenuInflater().inflate(R.menu.preview, menu);
        menu.findItem(R.id.action_print).setVisible(BuildConfig.DEBUG);
        menu.findItem(R.id.action_get).setVisible(BuildConfig.DEBUG);
        return super.onCreateOptionsMenu(menu);
    }

    @Override
    public boolean onOptionsItemSelected(MenuItem item) {
        switch (item.getItemId()) {
            case R.id.action_rotate:
                if (ORIENTATION_PORTRAIT == getResources().getConfiguration().orientation) {
                    setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE);
                } else {
                    setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_PORTRAIT);
                }
                return true;
            case R.id.action_edit:
                startActivityForResult(NoteEditActivity.getOpenIntent(this, mNote.getId(), false), REQ_EDIT);
                return true;
            case R.id.action_history:
                showHistoryDialog();
                return true;
            case R.id.action_attachments:
                showAttachmentsDialog();
                return true;
            case R.id.action_get:
                Observable.create(
                        new Observable.OnSubscribe<Void>() {
                            @Override
                            public void call(Subscriber<? super Void> subscriber) {
                                mEditorFragment.getContent();
                                subscriber.onNext(null);
                                subscriber.onCompleted();
                            }
                        })
                        .subscribeOn(Schedulers.io())
                        .observeOn(AndroidSchedulers.mainThread())
                        .subscribe();
                return true;
            case R.id.action_print:
                XLog.i(TAG + mNote.getContent());
        }
        return super.onOptionsItemSelected(item);
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == REQ_EDIT) {
            switch (resultCode) {
                case RESULT_OK:
                    mNote = NoteDataStore.getByLocalId(mNote.getId());
                    if (mNote == null) {
                        finish();
                    } else {
                        refresh();
                    }
                    break;
                case NoteEditActivity.RESULT_CONFLICT:
                    finish();
                    break;
            }
        }
    }

    @OnClick(R.id.tv_save)
    void push() {
        Observable.create(
                new Observable.OnSubscribe<Long>() {
                    @Override
                    public void call(Subscriber<? super Long> subscriber) {
                        if (!subscriber.isUnsubscribed()) {
                            NetworkUtils.checkNetwork();
                            NoteService.saveNote(mNote.getId());
                            subscriber.onNext(mNote.getId());
                            subscriber.onCompleted();
                        }
                    }
                })
                .subscribeOn(Schedulers.io())
                .observeOn(AndroidSchedulers.mainThread())
                .doOnSubscribe(new Action0() {
                    @Override
                    public void call() {
                        DialogDisplayer.showProgress(NotePreviewActivity.this, R.string.saving_note);
                    }
                })
                .subscribe(new Observer<Long>() {
                    @Override
                    public void onCompleted() {
                        DialogDisplayer.dismissProgress();
                    }

                    @Override
                    public void onError(Throwable e) {
                        DialogDisplayer.dismissProgress();
                        ToastUtils.show(NotePreviewActivity.this, e.getMessage());
                    }

                    @Override
                    public void onNext(Long aLong) {
                        mNote = NoteDataStore.getByLocalId(mNote.getId());
                        mNote.setIsDirty(false);
                        mNote.save();
                        refresh();
                    }
                });
    }

    @OnClick(R.id.tv_revert)
    void revert() {
        if (!NetworkUtils.isNetworkAvailable()) {
            ToastUtils.showNetworkUnavailable(this);
            return;
        }
        Observable.create(
                new Observable.OnSubscribe<Boolean>() {
                    @Override
                    public void call(Subscriber<? super Boolean> subscriber) {
                        if (!subscriber.isUnsubscribed()) {
                            subscriber.onNext(NoteService.revertNote(mNote.getNoteId()));
                            subscriber.onCompleted();
                        }
                    }
                })
                .subscribeOn(Schedulers.io())
                .observeOn(AndroidSchedulers.mainThread())
                .doOnSubscribe(new Action0() {
                    @Override
                    public void call() {
                        DialogDisplayer.showProgress(NotePreviewActivity.this, R.string.reverting);
                    }
                })
                .doOnCompleted(new Action0() {
                    @Override
                    public void call() {
                        DialogDisplayer.dismissProgress();
                    }
                })
                .subscribe(new Action1<Boolean>() {
                    @Override
                    public void call(Boolean isSucceed) {
                        if (isSucceed) {
                            mNote = NoteDataStore.getByServerId(mNote.getNoteId());
                            refresh();
                        }
                    }
                });

    }

    @Override
    public Uri createImage(String filePath) {
        return null;
    }

    private void showHistoryDialog() {
        if (NetworkUtils.isNetworkAvailable() && !mNote.isLocalNote()) {
            loadServerHistoryList();
        } else {
            showLocalHistoryDialog();
        }
    }

    private void loadServerHistoryList() {
        Observable.create(
                new Observable.OnSubscribe<List<NoteHistoryMeta>>() {
                    @Override
                    public void call(Subscriber<? super List<NoteHistoryMeta>> subscriber) {
                        if (!subscriber.isUnsubscribed()) {
                            HistoryListRe re = RetrofitUtils.excuteWithException(
                                    ApiProvider.getInstance().getNoteApi().getHistories(mNote.getNoteId()));
                            if (!re.isOk()) {
                                throw new IllegalStateException(re.getMsg());
                            }
                            subscriber.onNext(re.getItem() == null ? new ArrayList<NoteHistoryMeta>() : re.getItem());
                            subscriber.onCompleted();
                        }
                    }
                })
                .subscribeOn(Schedulers.io())
                .observeOn(AndroidSchedulers.mainThread())
                .doOnSubscribe(new Action0() {
                    @Override
                    public void call() {
                        DialogDisplayer.showProgress(NotePreviewActivity.this, R.string.progress_dialog_loading_msg);
                    }
                })
                .subscribe(new Observer<List<NoteHistoryMeta>>() {
                    @Override
                    public void onCompleted() {
                        DialogDisplayer.dismissProgress();
                    }

                    @Override
                    public void onError(Throwable e) {
                        DialogDisplayer.dismissProgress();
                        showLocalHistoryDialog();
                    }

                    @Override
                    public void onNext(List<NoteHistoryMeta> metas) {
                        if (metas.isEmpty()) {
                            showLocalHistoryDialog();
                        } else {
                            showServerHistoryListDialog(metas);
                        }
                    }
                });
    }

    private void showServerHistoryListDialog(final List<NoteHistoryMeta> metas) {
        SimpleDateFormat format = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault());
        List<String> items = new ArrayList<>();
        for (NoteHistoryMeta meta : metas) {
            long time = TimeUtils.toTimestamp(meta.getUpdatedTimeData());
            items.add(format.format(new Date(time)));
        }
        new AlertDialog.Builder(this)
                .setTitle(R.string.note_history)
                .setItems(items.toArray(new String[0]), new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialog, int which) {
                        dialog.dismiss();
                        loadServerHistoryContent(metas.get(which));
                    }
                })
                .show();
    }

    private void loadServerHistoryContent(final NoteHistoryMeta meta) {
        Observable.create(
                new Observable.OnSubscribe<String>() {
                    @Override
                    public void call(Subscriber<? super String> subscriber) {
                        if (!subscriber.isUnsubscribed()) {
                            HistoryContentRe re = RetrofitUtils.excuteWithException(
                                    ApiProvider.getInstance().getNoteApi().getHistoryContent(mNote.getNoteId(), meta.getHistoryId()));
                            if (!re.isOk() || re.getItem() == null) {
                                throw new IllegalStateException(re.getMsg());
                            }
                            subscriber.onNext(re.getItem().getContent());
                            subscriber.onCompleted();
                        }
                    }
                })
                .subscribeOn(Schedulers.io())
                .observeOn(AndroidSchedulers.mainThread())
                .doOnSubscribe(new Action0() {
                    @Override
                    public void call() {
                        DialogDisplayer.showProgress(NotePreviewActivity.this, R.string.progress_dialog_loading_msg);
                    }
                })
                .subscribe(new Observer<String>() {
                    @Override
                    public void onCompleted() {
                        DialogDisplayer.dismissProgress();
                    }

                    @Override
                    public void onError(Throwable e) {
                        DialogDisplayer.dismissProgress();
                        ToastUtils.show(NotePreviewActivity.this, R.string.network_error);
                    }

                    @Override
                    public void onNext(String content) {
                        showHistoryContentDialog(TimeUtils.toTimeFormat(TimeUtils.toTimestamp(meta.getUpdatedTimeData())), content);
                    }
                });
    }

    private void showLocalHistoryDialog() {
        List<NoteHistory> histories = NoteHistoryDataStore.getByNoteLocalId(mNote.getId());
        if (histories.isEmpty()) {
            ToastUtils.show(this, R.string.no_history);
            return;
        }
        List<String> items = new ArrayList<>();
        SimpleDateFormat format = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault());
        for (NoteHistory history : histories) {
            String preview = getPlainText(history.getContent());
            if (preview.length() > 40) {
                preview = preview.substring(0, 40) + "…";
            }
            items.add(format.format(new Date(history.getUpdatedTime()))
                    + (TextUtils.isEmpty(preview) ? "" : "\n" + preview));
        }
        new AlertDialog.Builder(this)
                .setTitle(R.string.note_history)
                .setItems(items.toArray(new String[0]), new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialog, int which) {
                        dialog.dismiss();
                        NoteHistory history = histories.get(which);
                        showHistoryContentDialog(TimeUtils.toTimeFormat(history.getUpdatedTime()), history.getContent());
                    }
                })
                .show();
    }

    private void showHistoryContentDialog(String title, final String content) {
        ScrollView scrollView = new ScrollView(this);
        TextView textView = new TextView(this);
        int padding = (int) (16 * getResources().getDisplayMetrics().density);
        textView.setPadding(padding, padding, padding, padding);
        textView.setTextIsSelectable(true);
        textView.setTypeface(Typeface.MONOSPACE);
        textView.setTextSize(13);
        textView.setText(content);
        scrollView.addView(textView);
        new AlertDialog.Builder(this)
                .setTitle(title)
                .setView(scrollView)
                .setPositiveButton(R.string.restore_this_version, new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialog, int which) {
                        dialog.dismiss();
                        confirmRestoreHistory(content);
                    }
                })
                .setNegativeButton(R.string.cancel, null)
                .show();
    }

    private void confirmRestoreHistory(final String content) {
        new AlertDialog.Builder(this)
                .setTitle(R.string.restore_this_version)
                .setMessage(R.string.are_you_sure_to_restore_history)
                .setPositiveButton(R.string.confirm, new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialog, int which) {
                        dialog.dismiss();
                        mNote.setContent(content);
                        mNote.setIsDirty(true);
                        mNote.update();
                        refresh();
                    }
                })
                .setNegativeButton(R.string.cancel, null)
                .show();
    }

    private void showAttachmentsDialog() {
        List<NoteFile> attachments = new ArrayList<>();
        for (NoteFile noteFile : NoteFileService.getRelatedNoteFiles(mNote.getId())) {
            if (noteFile.isAttach()) {
                attachments.add(noteFile);
            }
        }
        if (attachments.isEmpty()) {
            ToastUtils.show(this, R.string.no_attachments);
            return;
        }
        List<String> items = new ArrayList<>();
        for (NoteFile attachment : attachments) {
            items.add(TextUtils.isEmpty(attachment.getTitle()) ? attachment.getServerId() : attachment.getTitle());
        }
        new AlertDialog.Builder(this)
                .setTitle(R.string.attachments)
                .setItems(items.toArray(new String[0]), new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialog, int which) {
                        dialog.dismiss();
                        downloadAndOpenAttachment(attachments.get(which));
                    }
                })
                .show();
    }

    private void downloadAndOpenAttachment(final NoteFile attachment) {
        if (!NetworkUtils.isNetworkAvailable()) {
            ToastUtils.showNetworkUnavailable(this);
            return;
        }
        Observable.create(
                new Observable.OnSubscribe<File>() {
                    @Override
                    public void call(Subscriber<? super File> subscriber) {
                        if (!subscriber.isUnsubscribed()) {
                            try {
                                subscriber.onNext(NoteFileService.downloadAttach(attachment));
                                subscriber.onCompleted();
                            } catch (IOException e) {
                                subscriber.onError(e);
                            }
                        }
                    }
                })
                .subscribeOn(Schedulers.io())
                .observeOn(AndroidSchedulers.mainThread())
                .doOnSubscribe(new Action0() {
                    @Override
                    public void call() {
                        DialogDisplayer.showProgress(NotePreviewActivity.this, R.string.downloading);
                    }
                })
                .subscribe(new Observer<File>() {
                    @Override
                    public void onCompleted() {
                        DialogDisplayer.dismissProgress();
                    }

                    @Override
                    public void onError(Throwable e) {
                        DialogDisplayer.dismissProgress();
                        ToastUtils.show(NotePreviewActivity.this, R.string.download_error);
                    }

                    @Override
                    public void onNext(File file) {
                        ToastUtils.show(NotePreviewActivity.this, R.string.download_successful);
                        OpenUtils.openFile(NotePreviewActivity.this, file);
                    }
                });
    }

    private String getPlainText(String content) {
        if (content == null) {
            return "";
        }
        return content.replaceAll("<[^>]+>", " ").replaceAll("\\s+", " ").trim();
    }

    @Override
    public Uri createAttach(String filePath) {
        return null;
    }

    @Override
    public void onInitialized() {
        refresh();
    }

    private void refresh() {
        //TODO: animation
        mActionContainer.setVisibility(mNote.isDirty() ? View.VISIBLE : View.GONE);
        mRevertBtn.setVisibility(mNote.getUsn() > 0 ? View.VISIBLE : View.GONE);

        mEditorFragment.setTitle(TextUtils.isEmpty(mNote.getTitle()) ? getString(R.string.untitled) : mNote.getTitle());
        mEditorFragment.setContent(mNote.getContent());
    }
}
