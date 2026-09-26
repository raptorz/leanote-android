package com.github.gemsnote.network;

import com.elvishew.xlog.XLog;
import com.facebook.stetho.okhttp3.StethoInterceptor;

import com.github.gemsnote.BuildConfig;
import com.github.gemsnote.model.Account;
import com.github.gemsnote.network.api.AuthApi;
import com.github.gemsnote.network.api.NoteApi;
import com.github.gemsnote.network.api.NotebookApi;
import com.github.gemsnote.network.api.TagApi;
import com.github.gemsnote.network.api.UserApi;
import com.github.gemsnote.network.api.SystemApi;

import java.io.IOException;
import java.util.concurrent.TimeUnit;

import okhttp3.HttpUrl;
import okhttp3.Interceptor;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;
import okhttp3.logging.HttpLoggingInterceptor;
import retrofit2.Retrofit;

public class ApiProvider {

    private Retrofit mApiRetrofit;
    private String mHost;

    private static class SingletonHolder {
        private final static ApiProvider INSTANCE = new ApiProvider();
    }

    public static ApiProvider getInstance() {
        Account account = Account.getCurrent();
        if (account != null && (SingletonHolder.INSTANCE.mApiRetrofit == null
                || !normalizeHost(account.getHost()).equals(SingletonHolder.INSTANCE.mHost))) {
            SingletonHolder.INSTANCE.init(account.getHost());
        }
        return SingletonHolder.INSTANCE;
    }

    private ApiProvider() {
    }

    public void init(String host) {
        String normalizedHost = normalizeHost(host);
        OkHttpClient.Builder builder = new OkHttpClient.Builder()
                .addNetworkInterceptor(new Interceptor() {
                    @Override
                    public Response intercept(Chain chain) throws IOException {
                        Request request = chain.request();
                        HttpUrl url = request.url();
                        String path = url.encodedPath();
                        HttpUrl newUrl = url;
                        if (shouldAddTokenToQuery(path)) {
                            Account account = Account.getCurrent();
                            if (account == null || account.getAccessToken() == null
                                    || account.getAccessToken().isEmpty()) {
                                return chain.proceed(request);
                            }
                            newUrl = url.newBuilder()
                                    .addQueryParameter("token", account.getAccessToken())
                                    .build();
                        }
                        Request newRequest = request.newBuilder()
                                .url(newUrl)
                                .build();
                        return chain.proceed(newRequest);
                    }
                });
        if (BuildConfig.DEBUG) {
            HttpLoggingInterceptor interceptor = new HttpLoggingInterceptor(new HttpLoggingInterceptor.Logger() {
                @Override
                public void log(String message) {
                    XLog.d(message);
                }
            });
            interceptor.setLevel(HttpLoggingInterceptor.Level.BODY);
            builder.addNetworkInterceptor(interceptor);
            builder.addNetworkInterceptor(new StethoInterceptor());
        }
        builder.connectTimeout(20, TimeUnit.SECONDS).readTimeout(20, TimeUnit.SECONDS);
        OkHttpClient client = builder.build();
        mApiRetrofit = new Retrofit.Builder()
                .baseUrl(normalizedHost + "/api2/")
                .client(client)
                .addConverterFactory(new LeaResponseConverterFactory())
                .build();
        mHost = normalizedHost;
    }

    private static boolean shouldAddTokenToQuery(String path) {
        return !path.endsWith("/api2/auth/login")
                && !path.endsWith("/api2/auth/register")
                && !path.endsWith("/api2/system/version");
    }

    private static String normalizeHost(String host) {
        if (host == null) {
            return "";
        }
        while (host.endsWith("/")) {
            host = host.substring(0, host.length() - 1);
        }
        return host;
    }

    public AuthApi getAuthApi() {
        return mApiRetrofit.create(AuthApi.class);
    }

    public NoteApi getNoteApi() {
        return mApiRetrofit.create(NoteApi.class);
    }

    public UserApi getUserApi() {
        return mApiRetrofit.create(UserApi.class);
    }

    public NotebookApi getNotebookApi() {
        return mApiRetrofit.create(NotebookApi.class);
    }

    public TagApi getTagApi() {
        return mApiRetrofit.create(TagApi.class);
    }

    public SystemApi getSystemApi() {
        return mApiRetrofit.create(SystemApi.class);
    }

}
