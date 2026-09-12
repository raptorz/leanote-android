package com.github.gemsnote.service;

import com.github.gemsnote.database.AccountDataStore;
import com.github.gemsnote.model.Account;
import com.github.gemsnote.model.Authentication;
import com.github.gemsnote.model.BaseResponse;
import com.github.gemsnote.model.User;
import com.github.gemsnote.network.ApiProvider;
import com.github.gemsnote.utils.RetrofitUtils;

import java.util.List;

import rx.Observable;

public class AccountService {

    public static Observable<BaseResponse> register(String email, String password) {
        return RetrofitUtils.create(ApiProvider.getInstance().getAuthApi().register(email, password));
    }

    public static Observable<Authentication> login(String email, String password) {
        return RetrofitUtils.create(ApiProvider.getInstance().getAuthApi().login(email, password));
    }

    public static Observable<User> getInfo(String userId) {
        return RetrofitUtils.create(ApiProvider.getInstance().getUserApi().getInfo(userId));
    }

    public static long saveToAccount(Authentication authentication, String host) {
        Account localAccount = AccountDataStore.getAccount(authentication.getEmail(), host);
        if (localAccount == null) {
            localAccount = new Account();
        }
        localAccount.setHost(host);
        localAccount.setEmail(authentication.getEmail());
        localAccount.setAccessToken(authentication.getAccessToken());
        localAccount.setUserId(authentication.getUserId());
        localAccount.setUserName(authentication.getUserName());
        localAccount.save();
        return localAccount.getLocalUserId();
    }

    public static void saveToAccount(User user, String host) {
        Account localAccount = AccountDataStore.getAccount(user.getEmail(), host);
        if (localAccount == null) {
            localAccount = new Account();
        }
        localAccount.setHost(host);
        localAccount.setEmail(user.getEmail());
        localAccount.setUserId(user.getUserId());
        localAccount.setUserName(user.getUserName());
        localAccount.setAvatar(user.getAvatar());
        localAccount.setVerified(user.isVerified());
        localAccount.save();
    }

    public static void logout() {
        Account account = Account.getCurrent();
        account.setAccessToken("");
        account.update();
    }

    public static Observable<BaseResponse> changePassword(String oldPassword, String newPassword) {
        return RetrofitUtils.create(ApiProvider.getInstance().getUserApi().updatePassword(oldPassword, newPassword));
    }

    public static Observable<BaseResponse> changeUserName(String userName) {
        return RetrofitUtils.create(ApiProvider.getInstance().getUserApi().updateUsername(userName));
    }

    public static List<Account> getAccountList() {
        return AccountDataStore.getAccountListWithToken();
    }

    public static boolean isSignedIn() {
        return Account.getCurrent() != null;
    }
}
