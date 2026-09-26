package com.github.gemsnote.utils;


import com.github.gemsnote.Gemsnote;
import com.github.gemsnote.R;

import java.io.IOException;

import retrofit2.Call;
import retrofit2.Response;
import rx.Observable;
import rx.Subscriber;

public class RetrofitUtils {
    public static <T> Observable<T> create(final Call<T> call) {
        return Observable.create(new Observable.OnSubscribe<T>() {

            @Override
            public void call(Subscriber<? super T> subscriber) {
                if (!subscriber.isUnsubscribed()) {
                    try {
                        Response<T> response = call.execute();
                        if (response.isSuccessful()) {
                            if (response.body() == null) {
                                subscriber.onError(new IllegalStateException("empty response"));
                            } else {
                                subscriber.onNext(response.body());
                                subscriber.onCompleted();
                            }
                        } else {
                            subscriber.onError(new IllegalStateException("HTTP " + response.code()));
                        }
                    } catch (IOException e) {
                        subscriber.onError(new IllegalStateException("network error", e));
                    }
                }
            }
        });
    }

    public static <T> T excute(Call<T> call) {
        try {
            Response<T> response = call.execute();
            if (response.isSuccessful() && response.body() != null) {
                return response.body();
            }
        } catch (IOException e) {
            e.printStackTrace();
        }
        return null;
    }

    public static <T> T excuteWithException(Call<T> call) {
        try {
            Response<T> response = call.execute();
            if (response.isSuccessful() && response.body() != null) {
                T body = response.body();
                if (body instanceof com.github.gemsnote.model.BaseResponse
                        && !((com.github.gemsnote.model.BaseResponse) body).isOk()) {
                    throw new IllegalStateException(((com.github.gemsnote.model.BaseResponse) body).getMsg());
                }
                return body;
            } else {
                throw new IllegalStateException("HTTP " + response.code());
            }
        } catch (IOException e) {
            throw new IllegalStateException(Gemsnote.getContext().getString(R.string.network_error), e);
        }
    }
}
