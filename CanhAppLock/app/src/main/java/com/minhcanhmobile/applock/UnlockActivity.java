package com.minhcanhmobile.applock;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.hardware.biometrics.BiometricPrompt;
import android.os.Bundle;
import android.os.CancellationSignal;
import android.text.InputFilter;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.view.WindowManager;
import android.view.inputmethod.EditorInfo;
import android.widget.Button;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.util.concurrent.Executor;

public class UnlockActivity extends Activity {
    static final String EXTRA_TARGET_PACKAGE = "target_package";
    static final String EXTRA_ADMIN_MODE = "admin_mode";

    private String targetPackage;
    private boolean adminMode;
    private boolean completed;
    private CancellationSignal biometricCancellation;
    private EditText pinInput;
    private TextView errorText;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_SECURE);
        readIntent(getIntent());
        if (!AppPrefs.hasPin(this)) {
            cancelAndExit();
            return;
        }
        buildUi();
        if (AppPrefs.isBiometricEnabled(this)) showBiometricPrompt();
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        readIntent(intent);
        completed = false;
        if (AppPrefs.isBiometricEnabled(this)) showBiometricPrompt();
    }

    private void readIntent(Intent intent) {
        targetPackage = intent.getStringExtra(EXTRA_TARGET_PACKAGE);
        adminMode = intent.getBooleanExtra(EXTRA_ADMIN_MODE, false);
        if (targetPackage == null) targetPackage = "";
    }

    private void buildUi() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setGravity(Gravity.CENTER_HORIZONTAL);
        root.setPadding(dp(28), dp(48), dp(28), dp(28));
        root.setBackgroundColor(Color.rgb(247, 249, 253));

        ImageView icon = new ImageView(this);
        LinearLayout.LayoutParams iconParams = new LinearLayout.LayoutParams(dp(82), dp(82));
        iconParams.bottomMargin = dp(18);
        try {
            if (adminMode) {
                icon.setImageResource(com.minhcanhmobile.applock.R.drawable.ic_app_lock);
            } else {
                ApplicationInfo info = getPackageManager().getApplicationInfo(targetPackage, 0);
                icon.setImageDrawable(info.loadIcon(getPackageManager()));
            }
        } catch (Exception ignored) {
            icon.setImageResource(com.minhcanhmobile.applock.R.drawable.ic_app_lock);
        }
        root.addView(icon, iconParams);

        TextView title = new TextView(this);
        title.setText("Ứng dụng đã khóa");
        title.setTextSize(26);
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        title.setTextColor(Color.rgb(24, 31, 48));
        title.setGravity(Gravity.CENTER);
        root.addView(title, matchWrap());

        TextView subtitle = new TextView(this);
        subtitle.setText(adminMode
                ? "Xác thực để thay đổi cài đặt khóa"
                : "Dùng vân tay, khuôn mặt hoặc mã PIN để mở");
        subtitle.setTextSize(15);
        subtitle.setTextColor(Color.rgb(91, 101, 122));
        subtitle.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams subtitleParams = matchWrap();
        subtitleParams.topMargin = dp(8);
        subtitleParams.bottomMargin = dp(28);
        root.addView(subtitle, subtitleParams);

        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(dp(20), dp(20), dp(20), dp(20));
        GradientDrawable cardBg = new GradientDrawable();
        cardBg.setColor(Color.WHITE);
        cardBg.setCornerRadius(dp(18));
        card.setBackground(cardBg);
        card.setElevation(dp(4));
        LinearLayout.LayoutParams cardParams = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        root.addView(card, cardParams);

        TextView pinLabel = new TextView(this);
        pinLabel.setText("Mã PIN của Cảnh App Lock");
        pinLabel.setTextSize(14);
        pinLabel.setTextColor(Color.rgb(63, 70, 89));
        card.addView(pinLabel, matchWrap());

        pinInput = new EditText(this);
        pinInput.setInputType(InputType.TYPE_CLASS_NUMBER | InputType.TYPE_NUMBER_VARIATION_PASSWORD);
        pinInput.setFilters(new InputFilter[]{new InputFilter.LengthFilter(8)});
        pinInput.setHint("Nhập 4–8 số");
        pinInput.setTextSize(22);
        pinInput.setSingleLine(true);
        pinInput.setImeOptions(EditorInfo.IME_ACTION_DONE);
        LinearLayout.LayoutParams inputParams = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, dp(58));
        inputParams.topMargin = dp(6);
        card.addView(pinInput, inputParams);

        errorText = new TextView(this);
        errorText.setTextSize(13);
        errorText.setTextColor(Color.rgb(198, 40, 40));
        errorText.setVisibility(View.GONE);
        LinearLayout.LayoutParams errorParams = matchWrap();
        errorParams.topMargin = dp(5);
        card.addView(errorText, errorParams);

        Button unlockButton = new Button(this);
        unlockButton.setText("Mở khóa");
        unlockButton.setTextColor(Color.WHITE);
        unlockButton.setTextSize(16);
        unlockButton.setAllCaps(false);
        GradientDrawable buttonBg = new GradientDrawable();
        buttonBg.setColor(Color.rgb(49, 87, 213));
        buttonBg.setCornerRadius(dp(14));
        unlockButton.setBackground(buttonBg);
        LinearLayout.LayoutParams buttonParams = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, dp(54));
        buttonParams.topMargin = dp(14);
        card.addView(unlockButton, buttonParams);

        unlockButton.setOnClickListener(v -> verifyPin());
        pinInput.setOnEditorActionListener((v, actionId, event) -> {
            if (actionId == EditorInfo.IME_ACTION_DONE) {
                verifyPin();
                return true;
            }
            return false;
        });

        if (AppPrefs.isBiometricEnabled(this)) {
            Button biometricButton = new Button(this);
            biometricButton.setText("Dùng vân tay / khuôn mặt");
            biometricButton.setTextSize(15);
            biometricButton.setAllCaps(false);
            LinearLayout.LayoutParams biometricParams = new LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT, dp(52));
            biometricParams.topMargin = dp(16);
            root.addView(biometricButton, biometricParams);
            biometricButton.setOnClickListener(v -> showBiometricPrompt());
        }

        TextView privacy = new TextView(this);
        privacy.setText("Sinh trắc học được Android xử lý; app không nhận hoặc lưu dữ liệu vân tay/khuôn mặt.");
        privacy.setTextSize(12);
        privacy.setTextColor(Color.rgb(112, 121, 142));
        privacy.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams privacyParams = matchWrap();
        privacyParams.topMargin = dp(22);
        root.addView(privacy, privacyParams);

        setContentView(root);
    }

    private void verifyPin() {
        long remaining = AppPrefs.getLockedUntil(this) - System.currentTimeMillis();
        if (remaining > 0) {
            showError("Thử lại sau " + ((remaining + 999) / 1000) + " giây");
            return;
        }
        String pin = pinInput.getText().toString();
        if (pin.length() < 4) {
            showError("Mã PIN phải có ít nhất 4 số");
            return;
        }
        if (AppPrefs.verifyPin(this, pin)) {
            AppPrefs.clearFailedAttempts(this);
            unlockSuccess();
        } else {
            AppPrefs.recordFailedAttempt(this);
            pinInput.setText("");
            long lockedFor = AppPrefs.getLockedUntil(this) - System.currentTimeMillis();
            showError(lockedFor > 0
                    ? "Sai 5 lần. Vui lòng thử lại sau 30 giây"
                    : "Mã PIN chưa đúng");
        }
    }

    private void showBiometricPrompt() {
        if (completed || !AppPrefs.isBiometricEnabled(this)) return;
        try {
            if (biometricCancellation != null) biometricCancellation.cancel();
            biometricCancellation = new CancellationSignal();
            Executor executor = getMainExecutor();
            BiometricPrompt prompt = new BiometricPrompt.Builder(this)
                    .setTitle("Mở khóa ứng dụng")
                    .setSubtitle("Xác thực bằng vân tay hoặc khuôn mặt")
                    .setConfirmationRequired(false)
                    .setNegativeButton("Dùng mã PIN", executor, (dialog, which) -> {
                        pinInput.requestFocus();
                    })
                    .build();
            prompt.authenticate(biometricCancellation, executor,
                    new BiometricPrompt.AuthenticationCallback() {
                        @Override
                        public void onAuthenticationSucceeded(
                                BiometricPrompt.AuthenticationResult result) {
                            super.onAuthenticationSucceeded(result);
                            AppPrefs.clearFailedAttempts(UnlockActivity.this);
                            unlockSuccess();
                        }

                        @Override
                        public void onAuthenticationFailed() {
                            super.onAuthenticationFailed();
                            showError("Không nhận diện được, anh thử lại nhé");
                        }

                        @Override
                        public void onAuthenticationError(int errorCode, CharSequence errString) {
                            super.onAuthenticationError(errorCode, errString);
                            // Cancellation or unavailable biometrics leaves PIN as a safe fallback.
                        }
                    });
        } catch (Exception ignored) {
            showError("Máy chưa cài sinh trắc học; anh có thể dùng mã PIN");
        }
    }

    private void unlockSuccess() {
        if (completed) return;
        completed = true;
        if (biometricCancellation != null) biometricCancellation.cancel();
        if (adminMode) {
            setResult(RESULT_OK);
        } else {
            LockSession.grant(targetPackage);
        }
        finish();
        overridePendingTransition(0, 0);
    }

    private void showError(String message) {
        errorText.setText(message);
        errorText.setVisibility(View.VISIBLE);
    }

    @Override
    public void onBackPressed() {
        if (adminMode) {
            setResult(RESULT_CANCELED);
            finish();
        } else {
            cancelAndExit();
        }
    }

    private void cancelAndExit() {
        completed = true;
        Intent home = new Intent(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_HOME)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        try {
            startActivity(home);
        } catch (Exception ignored) {
            // If the launcher cannot be opened, closing still hides the lock screen.
        }
        finish();
        overridePendingTransition(0, 0);
    }

    @Override
    protected void onDestroy() {
        if (biometricCancellation != null) biometricCancellation.cancel();
        super.onDestroy();
    }

    private LinearLayout.LayoutParams matchWrap() {
        return new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT);
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }
}
