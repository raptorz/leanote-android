package com.github.gemsnote.utils;


import android.content.Context;
import android.net.ConnectivityManager;
import android.net.NetworkInfo;

import com.github.gemsnote.Gemsnote;
import com.github.gemsnote.R;

public class NetworkUtils {

    private static NetworkInfo getActiveNetworkInfo(Context context) {
        if (context == null) {
            return null;
        }
        ConnectivityManager cm = (ConnectivityManager) context.getSystemService(Context.CONNECTIVITY_SERVICE);
        if (cm == null) {
            return null;
        }
        // note that this may return null if no network is currently active
        return cm.getActiveNetworkInfo();
    }

    public static boolean isNetworkAvailable() {
        NetworkInfo info = getActiveNetworkInfo(Gemsnote.getContext());
        return (info != null && info.isConnected());
    }

    public static void checkNetwork() throws NetworkUnavailableException {
        if (!isNetworkAvailable()) {
            throw new NetworkUnavailableException();
        }
    }

    public static class NetworkUnavailableException extends IllegalStateException {
        public NetworkUnavailableException() {
            super(Gemsnote.getContext().getResources().getString(R.string.network_is_unavailable));
        }
    }
}
