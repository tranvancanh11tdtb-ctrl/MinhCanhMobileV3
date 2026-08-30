package com.minhcanhmobile.applock;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ComponentName;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Bundle;
import android.provider.Settings;
import android.text.Editable;
import android.text.InputFilter;
import android.text.InputType;
import android.text.TextUtils;
import android.text.TextWatcher;
import android.view.Gravity;
import android.view.View;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.ScrollView;
import android.widget.Switch;
import android.widget.TextView;
import android.widget.Toast;

import java.text.Collator;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class MainActivity extends Activity {
    private static final int REQUEST_ADMIN_AUTH = 7001;
    private final ExecutorService loader = Executors.newSingleThreadExecutor();
    private final List<AppEntry> allApps = new ArrayList<>();

    private LinearLayout page;
    private LinearLayout appsContainer;
    private TextView statusText;
    private TextView appCountText;
    private EditText searchInput;
    private boolean uiBuilt;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_SECURE);
        showLoadingPage();
        if (AppPrefs.hasPin(this)) {
            Intent auth = new Intent(this, UnlockActivity.class)
                    .putExtra(UnlockActivity.EXTRA_TARGET_PACKAGE, getPackageName())
                    .putExtra(UnlockActivity.EXTRA_ADMIN_MODE, true);
            startActivityForResult(auth, REQUEST_ADMIN_AUTH);
        } else {
            showCreatePinDialog();
        }
    }

    private void showLoadingPage() {
        LinearLayout loading = new LinearLayout(this);
        loading.setOrientation(LinearLayout.VERTICAL);
        loading.setGravity(Gravity.CENTER);
        loading.setBackgroundColor(Color.rgb(247, 249, 253));
        ImageView logo = new ImageView(this);
        logo.setImageResource(R.drawable.ic_app_lock);
        loading.addView(logo, new LinearLayout.LayoutParams(dp(88), dp(88)));
        TextView name = new TextView(this);
        name.setText("Cảnh App Lock");
        name.setTextSize(24);
        name.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        name.setTextColor(Color.rgb(26, 34, 51));
        name.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams nameParams = wrapWrap();
        nameParams.topMargin = dp(16);
        loading.addView(name, nameParams);
        setContentView(loading);
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == REQUEST_ADMIN_AUTH) {
            if (resultCode == RESULT_OK) buildMainUi(); else finish();
        }
    }

    private void showCreatePinDialog() {
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.setPadding(dp(22), dp(6), dp(22), 0);

        TextView note = new TextView(this);
        note.setText("Tạo mã PIN riêng gồm 4–8 số. Anh vẫn có thể mở bằng vân tay hoặc khuôn mặt.");
        note.setTextSize(14);
        note.setTextColor(Color.rgb(70, 78, 96));
        body.addView(note, matchWrap());

        EditText first = pinField("Nhập mã PIN");
        EditText second = pinField("Nhập lại mã PIN");
        LinearLayout.LayoutParams firstParams = matchWrap();
        firstParams.topMargin = dp(14);
        body.addView(first, firstParams);
        body.addView(second, matchWrap());

        AlertDialog dialog = new AlertDialog.Builder(this)
                .setTitle("Thiết lập khóa lần đầu")
                .setView(body)
                .setCancelable(false)
                .setPositiveButton("Tạo mã", null)
                .create();
        dialog.setOnShowListener(ignored -> dialog.getButton(AlertDialog.BUTTON_POSITIVE)
                .setOnClickListener(v -> {
                    String a = first.getText().toString();
                    String b = second.getText().toString();
                    if (a.length() < 4 || a.length() > 8) {
                        first.setError("Mã PIN phải có 4–8 số");
                    } else if (!a.equals(b)) {
                        second.setError("Hai mã PIN chưa giống nhau");
                    } else if (!AppPrefs.savePin(this, a)) {
                        Toast.makeText(this, "Không thể lưu mã PIN", Toast.LENGTH_LONG).show();
                    } else {
                        dialog.dismiss();
                        buildMainUi();
                    }
                }));
        dialog.show();
    }

    private void buildMainUi() {
        if (uiBuilt) return;
        uiBuilt = true;
        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.setBackgroundColor(Color.rgb(245, 247, 251));

        page = new LinearLayout(this);
        page.setOrientation(LinearLayout.VERTICAL);
        page.setPadding(dp(18), dp(22), dp(18), dp(40));
        scroll.addView(page, matchWrap());

        addHeader();
        addPermissionCard();
        addSecurityCard();
        addAppListSection();
        setContentView(scroll);
        loadApps();
    }

    private void addHeader() {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        ImageView logo = new ImageView(this);
        logo.setImageResource(R.drawable.ic_app_lock);
        row.addView(logo, new LinearLayout.LayoutParams(dp(58), dp(58)));

        LinearLayout text = new LinearLayout(this);
        text.setOrientation(LinearLayout.VERTICAL);
        LinearLayout.LayoutParams textParams = new LinearLayout.LayoutParams(0,
                LinearLayout.LayoutParams.WRAP_CONTENT, 1f);
        textParams.leftMargin = dp(14);
        row.addView(text, textParams);

        TextView title = new TextView(this);
        title.setText("Cảnh App Lock");
        title.setTextSize(25);
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        title.setTextColor(Color.rgb(24, 31, 48));
        text.addView(title, matchWrap());

        TextView subtitle = new TextView(this);
        subtitle.setText("Khóa riêng tư cho điện thoại Samsung");
        subtitle.setTextSize(13);
        subtitle.setTextColor(Color.rgb(98, 107, 128));
        text.addView(subtitle, matchWrap());
        page.addView(row, matchWrap());
    }

    private void addPermissionCard() {
        LinearLayout card = card();
        LinearLayout.LayoutParams cardParams = matchWrap();
        cardParams.topMargin = dp(20);
        page.addView(card, cardParams);

        TextView heading = sectionTitle("Trạng thái bảo vệ");
        card.addView(heading, matchWrap());

        statusText = new TextView(this);
        statusText.setTextSize(14);
        statusText.setPadding(0, dp(8), 0, dp(10));
        card.addView(statusText, matchWrap());

        Button accessibility = actionButton("1. Bật dịch vụ khóa ứng dụng");
        accessibility.setOnClickListener(v -> {
            try {
                startActivity(new Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS));
            } catch (Exception e) {
                Toast.makeText(this, "Mở Cài đặt > Hỗ trợ tiếp cận", Toast.LENGTH_LONG).show();
            }
        });
        card.addView(accessibility, buttonParams());

        Button overlay = actionButton("2. Cho phép xuất hiện trên cùng");
        overlay.setOnClickListener(v -> {
            Intent intent = new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:" + getPackageName()));
            try {
                startActivity(intent);
            } catch (Exception e) {
                startActivity(new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION));
            }
        });
        LinearLayout.LayoutParams overlayParams = buttonParams();
        overlayParams.topMargin = dp(10);
        card.addView(overlay, overlayParams);

        TextView help = new TextView(this);
        help.setText("Nếu Samsung không cho bật dịch vụ: vào Thông tin ứng dụng → dấu ⋮ → Cho phép cài đặt bị hạn chế, rồi quay lại bật.");
        help.setTextSize(12);
        help.setTextColor(Color.rgb(104, 113, 135));
        LinearLayout.LayoutParams helpParams = matchWrap();
        helpParams.topMargin = dp(12);
        card.addView(help, helpParams);
        updatePermissionStatus();
    }

    private void addSecurityCard() {
        LinearLayout card = card();
        LinearLayout.LayoutParams cardParams = matchWrap();
        cardParams.topMargin = dp(14);
        page.addView(card, cardParams);
        card.addView(sectionTitle("Cách mở khóa"), matchWrap());

        Switch biometric = new Switch(this);
        biometric.setText("Vân tay hoặc khuôn mặt");
        biometric.setTextSize(16);
        biometric.setTextColor(Color.rgb(35, 43, 61));
        biometric.setChecked(AppPrefs.isBiometricEnabled(this));
        biometric.setPadding(0, dp(8), 0, dp(4));
        biometric.setOnCheckedChangeListener((buttonView, isChecked) -> {
            AppPrefs.setBiometricEnabled(this, isChecked);
            Toast.makeText(this, isChecked ? "Đã bật sinh trắc học" : "Sẽ chỉ dùng mã PIN",
                    Toast.LENGTH_SHORT).show();
        });
        card.addView(biometric, matchWrap());

        TextView pinInfo = new TextView(this);
        pinInfo.setText("Mã PIN riêng luôn dùng được làm phương án dự phòng.");
        pinInfo.setTextSize(13);
        pinInfo.setTextColor(Color.rgb(100, 108, 129));
        card.addView(pinInfo, matchWrap());

        Button changePin = secondaryButton("Đổi mã PIN");
        changePin.setOnClickListener(v -> showChangePinDialog());
        LinearLayout.LayoutParams changeParams = buttonParams();
        changeParams.topMargin = dp(10);
        card.addView(changePin, changeParams);
    }

    private void addAppListSection() {
        LinearLayout titleRow = new LinearLayout(this);
        titleRow.setOrientation(LinearLayout.HORIZONTAL);
        titleRow.setGravity(Gravity.CENTER_VERTICAL);
        LinearLayout.LayoutParams titleParams = matchWrap();
        titleParams.topMargin = dp(22);
        page.addView(titleRow, titleParams);

        TextView title = sectionTitle("Chọn ứng dụng cần khóa");
        titleRow.addView(title, new LinearLayout.LayoutParams(0,
                LinearLayout.LayoutParams.WRAP_CONTENT, 1f));
        appCountText = new TextView(this);
        appCountText.setText("Đang tải…");
        appCountText.setTextSize(13);
        appCountText.setTextColor(Color.rgb(96, 105, 125));
        titleRow.addView(appCountText, wrapWrap());

        searchInput = new EditText(this);
        searchInput.setHint("Tìm Zalo, Facebook, Thư viện…");
        searchInput.setSingleLine(true);
        searchInput.setTextSize(15);
        searchInput.setPadding(dp(16), 0, dp(16), 0);
        GradientDrawable searchBg = new GradientDrawable();
        searchBg.setColor(Color.WHITE);
        searchBg.setCornerRadius(dp(14));
        searchBg.setStroke(dp(1), Color.rgb(224, 228, 238));
        searchInput.setBackground(searchBg);
        LinearLayout.LayoutParams searchParams = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, dp(52));
        searchParams.topMargin = dp(10);
        page.addView(searchInput, searchParams);

        appsContainer = card();
        LinearLayout.LayoutParams appsParams = matchWrap();
        appsParams.topMargin = dp(12);
        page.addView(appsContainer, appsParams);

        ProgressBar progress = new ProgressBar(this);
        LinearLayout.LayoutParams progressParams = new LinearLayout.LayoutParams(dp(42), dp(42));
        progressParams.gravity = Gravity.CENTER_HORIZONTAL;
        progressParams.topMargin = dp(12);
        progressParams.bottomMargin = dp(12);
        appsContainer.addView(progress, progressParams);

        searchInput.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int start, int count, int after) {}
            @Override public void onTextChanged(CharSequence s, int start, int before, int count) {
                renderApps(s.toString());
            }
            @Override public void afterTextChanged(Editable s) {}
        });
    }

    private void loadApps() {
        loader.execute(() -> {
            PackageManager pm = getPackageManager();
            Intent launcher = new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER);
            List<ResolveInfo> resolved = pm.queryIntentActivities(launcher, 0);
            Set<String> seen = new HashSet<>();
            List<AppEntry> found = new ArrayList<>();
            for (ResolveInfo info : resolved) {
                if (info.activityInfo == null || info.activityInfo.applicationInfo == null) continue;
                String pkg = info.activityInfo.packageName;
                if (pkg == null || pkg.equals(getPackageName()) || !seen.add(pkg)) continue;
                if (pkg.equals("com.android.systemui") || pkg.equals("com.android.settings")) continue;
                ApplicationInfo applicationInfo = info.activityInfo.applicationInfo;
                String label = applicationInfo.loadLabel(pm).toString();
                found.add(new AppEntry(pkg, label, applicationInfo));
            }
            Collator collator = Collator.getInstance(new Locale("vi", "VN"));
            found.sort(Comparator.comparing((AppEntry entry) -> entry.label, collator));
            runOnUiThread(() -> {
                allApps.clear();
                allApps.addAll(found);
                renderApps(searchInput == null ? "" : searchInput.getText().toString());
            });
        });
    }

    private void renderApps(String query) {
        if (appsContainer == null || allApps.isEmpty()) return;
        String normalized = query == null ? "" : query.trim().toLowerCase(new Locale("vi", "VN"));
        appsContainer.removeAllViews();
        int visible = 0;
        int lockedCount = AppPrefs.getLockedApps(this).size();
        for (AppEntry entry : allApps) {
            if (!normalized.isEmpty()
                    && !entry.label.toLowerCase(new Locale("vi", "VN")).contains(normalized)
                    && !entry.packageName.toLowerCase(Locale.ROOT).contains(normalized)) continue;
            if (visible > 0) appsContainer.addView(divider(), new LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT, dp(1)));
            appsContainer.addView(appRow(entry), matchWrap());
            visible++;
        }
        if (visible == 0) {
            TextView empty = new TextView(this);
            empty.setText("Không tìm thấy ứng dụng");
            empty.setGravity(Gravity.CENTER);
            empty.setTextColor(Color.rgb(104, 113, 133));
            empty.setPadding(0, dp(22), 0, dp(22));
            appsContainer.addView(empty, matchWrap());
        }
        appCountText.setText(lockedCount + " ứng dụng đang khóa");
    }

    private View appRow(AppEntry entry) {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(0, dp(8), 0, dp(8));

        ImageView icon = new ImageView(this);
        try {
            icon.setImageDrawable(entry.applicationInfo.loadIcon(getPackageManager()));
        } catch (Exception ignored) {
            icon.setImageResource(R.drawable.ic_app_lock);
        }
        row.addView(icon, new LinearLayout.LayoutParams(dp(46), dp(46)));

        LinearLayout labels = new LinearLayout(this);
        labels.setOrientation(LinearLayout.VERTICAL);
        LinearLayout.LayoutParams labelsParams = new LinearLayout.LayoutParams(0,
                LinearLayout.LayoutParams.WRAP_CONTENT, 1f);
        labelsParams.leftMargin = dp(12);
        row.addView(labels, labelsParams);

        TextView name = new TextView(this);
        name.setText(entry.label);
        name.setTextSize(16);
        name.setTextColor(Color.rgb(34, 42, 60));
        name.setMaxLines(1);
        name.setEllipsize(TextUtils.TruncateAt.END);
        labels.addView(name, matchWrap());

        TextView packageText = new TextView(this);
        packageText.setText(entry.packageName);
        packageText.setTextSize(11);
        packageText.setTextColor(Color.rgb(122, 131, 149));
        packageText.setMaxLines(1);
        packageText.setEllipsize(TextUtils.TruncateAt.MIDDLE);
        labels.addView(packageText, matchWrap());

        Switch toggle = new Switch(this);
        toggle.setChecked(AppPrefs.isAppLocked(this, entry.packageName));
        toggle.setContentDescription("Khóa " + entry.label);
        toggle.setOnCheckedChangeListener((buttonView, isChecked) -> {
            AppPrefs.setAppLocked(this, entry.packageName, isChecked);
            appCountText.setText(AppPrefs.getLockedApps(this).size() + " ứng dụng đang khóa");
            if (isChecked && (!isAccessibilityEnabled() || !Settings.canDrawOverlays(this))) {
                Toast.makeText(this, "Hãy bật đủ 2 quyền ở phía trên để khóa hoạt động",
                        Toast.LENGTH_LONG).show();
            }
        });
        row.addView(toggle, wrapWrap());
        row.setOnClickListener(v -> toggle.setChecked(!toggle.isChecked()));
        return row;
    }

    private void showChangePinDialog() {
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.setPadding(dp(22), 0, dp(22), 0);
        EditText oldPin = pinField("Mã PIN hiện tại");
        EditText newPin = pinField("Mã PIN mới (4–8 số)");
        EditText repeat = pinField("Nhập lại mã PIN mới");
        body.addView(oldPin, matchWrap());
        body.addView(newPin, matchWrap());
        body.addView(repeat, matchWrap());

        AlertDialog dialog = new AlertDialog.Builder(this)
                .setTitle("Đổi mã PIN")
                .setView(body)
                .setNegativeButton("Hủy", null)
                .setPositiveButton("Lưu", null)
                .create();
        dialog.setOnShowListener(ignored -> dialog.getButton(AlertDialog.BUTTON_POSITIVE)
                .setOnClickListener(v -> {
                    String oldValue = oldPin.getText().toString();
                    String newValue = newPin.getText().toString();
                    if (!AppPrefs.verifyPin(this, oldValue)) {
                        oldPin.setError("Mã PIN hiện tại chưa đúng");
                    } else if (newValue.length() < 4 || newValue.length() > 8) {
                        newPin.setError("Mã PIN phải có 4–8 số");
                    } else if (!newValue.equals(repeat.getText().toString())) {
                        repeat.setError("Hai mã PIN chưa giống nhau");
                    } else if (AppPrefs.savePin(this, newValue)) {
                        dialog.dismiss();
                        Toast.makeText(this, "Đã đổi mã PIN", Toast.LENGTH_SHORT).show();
                    }
                }));
        dialog.show();
    }

    private EditText pinField(String hint) {
        EditText field = new EditText(this);
        field.setHint(hint);
        field.setSingleLine(true);
        field.setInputType(InputType.TYPE_CLASS_NUMBER | InputType.TYPE_NUMBER_VARIATION_PASSWORD);
        field.setFilters(new InputFilter[]{new InputFilter.LengthFilter(8)});
        return field;
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (uiBuilt) updatePermissionStatus();
    }

    private void updatePermissionStatus() {
        if (statusText == null) return;
        boolean accessibility = isAccessibilityEnabled();
        boolean overlay = Settings.canDrawOverlays(this);
        if (accessibility && overlay) {
            statusText.setText("● Đang bảo vệ — app đã có đủ quyền");
            statusText.setTextColor(Color.rgb(31, 133, 75));
        } else {
            String missing = !accessibility && !overlay
                    ? "cần bật 2 quyền bên dưới"
                    : (!accessibility ? "chưa bật dịch vụ khóa" : "chưa cho phép xuất hiện trên cùng");
            statusText.setText("● Chưa hoạt động — " + missing);
            statusText.setTextColor(Color.rgb(198, 75, 45));
        }
    }

    private boolean isAccessibilityEnabled() {
        String enabled = Settings.Secure.getString(getContentResolver(),
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES);
        if (enabled == null) return false;
        ComponentName component = new ComponentName(this, AppLockAccessibilityService.class);
        String full = component.flattenToString();
        String shortName = component.flattenToShortString();
        TextUtils.SimpleStringSplitter splitter = new TextUtils.SimpleStringSplitter(':');
        splitter.setString(enabled);
        while (splitter.hasNext()) {
            String item = splitter.next();
            if (item.equalsIgnoreCase(full) || item.equalsIgnoreCase(shortName)) return true;
        }
        return false;
    }

    private LinearLayout card() {
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(dp(16), dp(16), dp(16), dp(16));
        GradientDrawable background = new GradientDrawable();
        background.setColor(Color.WHITE);
        background.setCornerRadius(dp(18));
        card.setBackground(background);
        card.setElevation(dp(2));
        return card;
    }

    private TextView sectionTitle(String text) {
        TextView title = new TextView(this);
        title.setText(text);
        title.setTextSize(18);
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        title.setTextColor(Color.rgb(29, 37, 55));
        return title;
    }

    private Button actionButton(String text) {
        Button button = new Button(this);
        button.setText(text);
        button.setTextColor(Color.WHITE);
        button.setTextSize(14);
        button.setAllCaps(false);
        GradientDrawable background = new GradientDrawable();
        background.setColor(Color.rgb(49, 87, 213));
        background.setCornerRadius(dp(13));
        button.setBackground(background);
        return button;
    }

    private Button secondaryButton(String text) {
        Button button = new Button(this);
        button.setText(text);
        button.setTextColor(Color.rgb(49, 87, 213));
        button.setTextSize(14);
        button.setAllCaps(false);
        GradientDrawable background = new GradientDrawable();
        background.setColor(Color.rgb(239, 243, 255));
        background.setCornerRadius(dp(13));
        button.setBackground(background);
        return button;
    }

    private View divider() {
        View line = new View(this);
        line.setBackgroundColor(Color.rgb(235, 238, 245));
        return line;
    }

    private LinearLayout.LayoutParams buttonParams() {
        return new LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(50));
    }

    private LinearLayout.LayoutParams matchWrap() {
        return new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT);
    }

    private LinearLayout.LayoutParams wrapWrap() {
        return new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT);
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    @Override
    protected void onDestroy() {
        loader.shutdownNow();
        super.onDestroy();
    }

    private static final class AppEntry {
        final String packageName;
        final String label;
        final ApplicationInfo applicationInfo;

        AppEntry(String packageName, String label, ApplicationInfo applicationInfo) {
            this.packageName = packageName;
            this.label = label;
            this.applicationInfo = applicationInfo;
        }
    }
}
