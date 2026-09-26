package com.github.gemsnote.ui;

import android.os.Bundle;
import androidx.appcompat.widget.Toolbar;
import android.view.View;
import android.widget.TextView;

import com.raizlabs.android.dbflow.config.FlowManager;
import com.raizlabs.android.dbflow.structure.database.transaction.Transaction;
import com.raizlabs.android.dbflow.structure.database.transaction.FastStoreModelTransaction;

import org.bson.types.ObjectId;
import com.github.gemsnote.BuildConfig;
import com.github.gemsnote.R;
import com.github.gemsnote.database.AppDataBase;
import com.github.gemsnote.model.Account;
import com.github.gemsnote.model.Note;
import com.github.gemsnote.utils.OpenUtils;
import com.github.gemsnote.utils.TestUtils;

import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.List;

import butterknife.BindView;
import butterknife.ButterKnife;
import butterknife.OnClick;
import rx.Observable;
import rx.Subscriber;
import rx.schedulers.Schedulers;

public class AboutActivity extends BaseActivity {

    @BindView(R.id.tv_version)
    TextView mVersionTv;
    @BindView(R.id.ll_debug)
    View mDebugPanel;


    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_about);
        initToolBar((Toolbar) findViewById(R.id.toolbar), true);
        ButterKnife.bind(this);

        mVersionTv.setText(BuildConfig.VERSION_NAME);
        mDebugPanel.setVisibility(BuildConfig.DEBUG ? View.VISIBLE : View.GONE);
    }

    @OnClick(R.id.ll_generate_random_note)
    void clickedVersion() {
        Observable.create(
                new Observable.OnSubscribe<Void>() {
                    @Override
                    public void call(Subscriber<? super Void> subscriber) {
                        String userId = Account.getCurrent().getUserId();
                        SecureRandom random = new SecureRandom();
                        String notebookId = new ObjectId().toString();
                        List<Note> notes = new ArrayList(8000);
                        for (int i = 0; i < 5000; i++) {
                            Note note = TestUtils.randomNote(random, notebookId, userId);
                            notes.add(note);
                        }
                        FastStoreModelTransaction fastStore = FastStoreModelTransaction
                                .insertBuilder(FlowManager.getModelAdapter(Note.class))
                                .addAll(notes)
                                .build();
                        Transaction transaction = FlowManager.getDatabase(AppDataBase.class).beginTransactionAsync(fastStore).build();
                        transaction.execute();
                    }
                }).subscribeOn(Schedulers.io())
                .subscribe();
    }

    @OnClick(R.id.ll_github)
    void clickedGithub() {
        OpenUtils.openUrl(this, "https://github.com/gemsnote/gemsnote");
    }

    @OnClick(R.id.ll_feedback)
    void clickedFeedback() {
        OpenUtils.openUrl(this, "https://github.com/gemsnote/gemsnote/issues");
    }

    @OnClick(R.id.thanks)
    void clickedThanks() {
        OpenUtils.openUrl(this, "https://github.com/gemsnote/gemsnote/graphs/contributors");
    }

}
