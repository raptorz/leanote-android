package org.houxg.leamonax.ui;

import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.text.TextUtils;

import com.bumptech.glide.Glide;

import org.houxg.leamonax.R;

import java.io.File;

import butterknife.BindView;
import butterknife.ButterKnife;

public class PictureViewerActivity extends BaseActivity {

    private static final String EXTRA_FILE_PATH = "extra.filePath";

    @BindView(R.id.big_image)
    android.widget.ImageView mBigImageView;


    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_picture_viewer);
        ButterKnife.bind(this);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            getWindow().setStatusBarColor(getResources().getColor(R.color.black));
        }

        String path = getIntent().getStringExtra(EXTRA_FILE_PATH);
        if (TextUtils.isEmpty(path)) {
            finish();
            return;
        }
        Uri uri = Uri.fromFile(new File(path));
        Glide.with(this).load(uri).into(mBigImageView);
    }

    public static Intent getOpenIntent(Context context, String path) {
        Intent intent = new Intent(context, PictureViewerActivity.class);
        intent.putExtra(EXTRA_FILE_PATH, path);
        return intent;
    }


}
