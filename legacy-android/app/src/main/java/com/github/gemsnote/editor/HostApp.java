package com.github.gemsnote.editor;

import android.webkit.JavascriptInterface;

import org.greenrobot.eventbus.EventBus;
import com.github.gemsnote.model.CompleteEvent;

public class HostApp {

    @JavascriptInterface
    public void loadCompleted() {
        EventBus.getDefault().post(new CompleteEvent());
    }

}
