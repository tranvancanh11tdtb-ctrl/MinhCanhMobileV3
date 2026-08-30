package com.minhcanhmobile.applock;

import android.content.Context;
import android.content.SharedPreferences;
import android.util.Base64;

import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.Collections;
import java.util.HashSet;
import java.util.Set;

import javax.crypto.SecretKeyFactory;
import javax.crypto.spec.PBEKeySpec;

final class AppPrefs {
    private static final String PREFS = "canh_app_lock_secure";
    private static final String KEY_PIN_SALT = "pin_salt";
    private static final String KEY_PIN_HASH = "pin_hash";
    private static final String KEY_LOCKED_APPS = "locked_apps";
    private static final String KEY_BIOMETRIC = "biometric_enabled";
    private static final String KEY_FAILED_ATTEMPTS = "failed_attempts";
    private static final String KEY_LOCKED_UNTIL = "locked_until";
    private static final int PBKDF2_ITERATIONS = 120_000;

    private AppPrefs() {}

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    static boolean hasPin(Context context) {
        return prefs(context).contains(KEY_PIN_HASH) && prefs(context).contains(KEY_PIN_SALT);
    }

    static boolean savePin(Context context, String pin) {
        try {
            byte[] salt = new byte[24];
            new SecureRandom().nextBytes(salt);
            byte[] hash = derivePin(pin, salt);
            prefs(context).edit()
                    .putString(KEY_PIN_SALT, Base64.encodeToString(salt, Base64.NO_WRAP))
                    .putString(KEY_PIN_HASH, Base64.encodeToString(hash, Base64.NO_WRAP))
                    .putInt(KEY_FAILED_ATTEMPTS, 0)
                    .putLong(KEY_LOCKED_UNTIL, 0L)
                    .apply();
            return true;
        } catch (Exception ignored) {
            return false;
        }
    }

    static boolean verifyPin(Context context, String pin) {
        try {
            String saltText = prefs(context).getString(KEY_PIN_SALT, "");
            String hashText = prefs(context).getString(KEY_PIN_HASH, "");
            if (saltText.isEmpty() || hashText.isEmpty()) return false;
            byte[] salt = Base64.decode(saltText, Base64.NO_WRAP);
            byte[] expected = Base64.decode(hashText, Base64.NO_WRAP);
            byte[] actual = derivePin(pin, salt);
            return MessageDigest.isEqual(expected, actual);
        } catch (Exception ignored) {
            return false;
        }
    }

    private static byte[] derivePin(String pin, byte[] salt) throws Exception {
        PBEKeySpec spec = new PBEKeySpec(pin.toCharArray(), salt, PBKDF2_ITERATIONS, 256);
        try {
            return SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
                    .generateSecret(spec)
                    .getEncoded();
        } finally {
            spec.clearPassword();
        }
    }

    static Set<String> getLockedApps(Context context) {
        Set<String> stored = prefs(context).getStringSet(KEY_LOCKED_APPS, Collections.emptySet());
        return new HashSet<>(stored == null ? Collections.emptySet() : stored);
    }

    static boolean isAppLocked(Context context, String packageName) {
        return getLockedApps(context).contains(packageName);
    }

    static void setAppLocked(Context context, String packageName, boolean locked) {
        Set<String> apps = getLockedApps(context);
        if (locked) apps.add(packageName); else apps.remove(packageName);
        prefs(context).edit().putStringSet(KEY_LOCKED_APPS, apps).apply();
    }

    static boolean isBiometricEnabled(Context context) {
        return prefs(context).getBoolean(KEY_BIOMETRIC, true);
    }

    static void setBiometricEnabled(Context context, boolean enabled) {
        prefs(context).edit().putBoolean(KEY_BIOMETRIC, enabled).apply();
    }

    static long getLockedUntil(Context context) {
        return prefs(context).getLong(KEY_LOCKED_UNTIL, 0L);
    }

    static void recordFailedAttempt(Context context) {
        SharedPreferences p = prefs(context);
        int attempts = p.getInt(KEY_FAILED_ATTEMPTS, 0) + 1;
        SharedPreferences.Editor editor = p.edit().putInt(KEY_FAILED_ATTEMPTS, attempts);
        if (attempts >= 5) {
            editor.putInt(KEY_FAILED_ATTEMPTS, 0)
                    .putLong(KEY_LOCKED_UNTIL, System.currentTimeMillis() + 30_000L);
        }
        editor.apply();
    }

    static void clearFailedAttempts(Context context) {
        prefs(context).edit().putInt(KEY_FAILED_ATTEMPTS, 0).putLong(KEY_LOCKED_UNTIL, 0L).apply();
    }
}
