package com.minhcanhmobile.applock;

import android.accessibilityservice.AccessibilityService;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;
import android.view.accessibility.AccessibilityEvent;

public class AppLockAccessibilityService extends AccessibilityService {
    private String lastProtectedPackage;
    private String lastLaunchPackage;
    private long lastLaunchAt;

    private final BroadcastReceiver screenReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            if (Intent.ACTION_SCREEN_OFF.equals(intent.getAction())) {
                LockSession.clear();
                lastProtectedPackage = null;
            }
        }
    };

    @Override
    protected void onServiceConnected() {
        super.onServiceConnected();
        LockSession.clear();
        IntentFilter filter = new IntentFilter(Intent.ACTION_SCREEN_OFF);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(screenReceiver, filter, Context.RECEIVER_NOT_EXPORTED);
        } else {
            registerReceiver(screenReceiver, filter);
        }
    }

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) {
        if (event == null || event.getPackageName() == null) return;
        int type = event.getEventType();
        if (type != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
                && type != AccessibilityEvent.TYPE_WINDOWS_CHANGED) return;

        String packageName = event.getPackageName().toString();
        if (packageName.isEmpty() || packageName.equals(getPackageName())) return;

        // System authentication and the notification shade are not app transitions.
        if (packageName.equals("com.android.systemui") || packageName.equals("android")) return;

        if (AppPrefs.isAppLocked(this, packageName)) {
            if (lastProtectedPackage != null && !lastProtectedPackage.equals(packageName)) {
                LockSession.revoke(lastProtectedPackage);
            }
            lastProtectedPackage = packageName;
            if (!LockSession.isGranted(packageName)) showLockScreen(packageName);
        } else {
            if (lastProtectedPackage != null) LockSession.revoke(lastProtectedPackage);
            lastProtectedPackage = null;
        }
    }

    private void showLockScreen(String packageName) {
        if (!AppPrefs.hasPin(this) || !Settings.canDrawOverlays(this)) return;
        long now = System.currentTimeMillis();
        if (packageName.equals(lastLaunchPackage) && now - lastLaunchAt < 800L) return;
        lastLaunchPackage = packageName;
        lastLaunchAt = now;

        Intent intent = new Intent(this, UnlockActivity.class)
                .putExtra(UnlockActivity.EXTRA_TARGET_PACKAGE, packageName)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK
                        | Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS
                        | Intent.FLAG_ACTIVITY_NO_ANIMATION
                        | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        try {
            startActivity(intent);
        } catch (Exception ignored) {
            Intent settings = new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:" + getPackageName()))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            try {
                startActivity(settings);
            } catch (Exception ignoredAgain) {
                // The setup screen explains how to grant the required permission.
            }
        }
    }

    void goHome() {
        performGlobalAction(GLOBAL_ACTION_HOME);
    }

    @Override
    public void onInterrupt() {
        LockSession.clear();
    }

    @Override
    public void onDestroy() {
        try {
            unregisterReceiver(screenReceiver);
        } catch (Exception ignored) {
            // Receiver may not have been registered if the service never connected.
        }
        LockSession.clear();
        super.onDestroy();
    }
}
