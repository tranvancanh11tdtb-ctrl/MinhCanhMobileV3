package com.minhcanhmobile.applock;

import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

final class LockSession {
    private static final Set<String> UNLOCKED = ConcurrentHashMap.newKeySet();

    private LockSession() {}

    static void grant(String packageName) {
        if (packageName != null && !packageName.isEmpty()) UNLOCKED.add(packageName);
    }

    static boolean isGranted(String packageName) {
        return packageName != null && UNLOCKED.contains(packageName);
    }

    static void revoke(String packageName) {
        if (packageName != null) UNLOCKED.remove(packageName);
    }

    static void clear() {
        UNLOCKED.clear();
    }
}
