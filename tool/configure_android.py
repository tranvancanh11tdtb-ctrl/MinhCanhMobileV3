from pathlib import Path
import shutil

package = 'vn.minhcanhmobile.minh_canh_mobile_v3'
base = Path('android/app/src/main')
manifest = base / 'AndroidManifest.xml'
s = manifest.read_text()
permissions = ['INTERNET', 'ACCESS_NETWORK_STATE', 'ACCESS_WIFI_STATE', 'CHANGE_WIFI_STATE', 'WAKE_LOCK', 'FOREGROUND_SERVICE', 'FOREGROUND_SERVICE_CONNECTED_DEVICE', 'POST_NOTIFICATIONS', 'USE_BIOMETRIC', 'CAMERA', 'BLUETOOTH_CONNECT', 'BLUETOOTH_SCAN']
for name in permissions:
    tag = f'<uses-permission android:name="android.permission.{name}" />'
    if f'android.permission.{name}' not in s:
        s = s.replace('<application', tag + '\n    <application', 1)
s = s.replace('android:label="minh_canh_mobile_v3"', 'android:label="Minh Cảnh Mobile"')
s = s.replace('<application', '<application android:usesCleartextTraffic="true"', 1)
s = s.replace('</application>', '<service android:name=".LanService" android:exported="false" android:foregroundServiceType="connectedDevice" android:stopWithTask="true" />\n    </application>')
manifest.write_text(s)
# local_auth requires an AppCompat launch theme, including older Android.
for styles in (base / 'res').glob('values*/styles.xml'):
    theme = styles.read_text()
    theme = theme.replace('parent="@android:style/Theme.Light.NoTitleBar"', 'parent="Theme.AppCompat.DayNight.NoActionBar"')
    theme = theme.replace('parent="@android:style/Theme.Black.NoTitleBar"', 'parent="Theme.AppCompat.DayNight.NoActionBar"')
    styles.write_text(theme)
kotlin = base / 'kotlin' / Path(package.replace('.', '/'))
kotlin.mkdir(parents=True, exist_ok=True)
(kotlin / 'MainActivity.kt').write_text('''package vn.minhcanhmobile.minh_canh_mobile_v3
import android.Manifest
import android.content.Intent
import android.os.Build
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterFragmentActivity() {
    private var lanChannel: MethodChannel? = null
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        lanChannel = MethodChannel(engine.dartExecutor.binaryMessenger, "vn.minhcanhmobile/lan")
        LanService.onStopRequested = { runOnUiThread { lanChannel?.invokeMethod("stopped", null) } }
        lanChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 311)
                        }
                        val intent = Intent(this, LanService::class.java).putExtra("address", call.argument<String>("address"))
                        if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
                        result.success(null)
                    } catch (e: Exception) { result.error("LAN_START", "Không thể bật kết nối nền", null) }
                }
                "stop" -> { stopService(Intent(this, LanService::class.java)); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }
    override fun onDestroy() {
        if (isFinishing) stopService(Intent(this, LanService::class.java))
        LanService.onStopRequested = null
        super.onDestroy()
    }
}
''')
(kotlin / 'LanService.kt').write_text('''package vn.minhcanhmobile.minh_canh_mobile_v3
import android.app.*
import android.content.Intent
import android.os.*
import android.content.pm.ServiceInfo

class LanService: Service() {
    companion object { var onStopRequested: (() -> Unit)? = null }
    private var wake: PowerManager.WakeLock? = null
    override fun onBind(intent: Intent?) = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "STOP_LAN") {
            onStopRequested?.invoke()
            stopSelf()
            return START_NOT_STICKY
        }
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel("mcm_lan", "Kết nối máy tính", NotificationManager.IMPORTANCE_LOW))
        val stopIntent = PendingIntent.getService(this, 311, Intent(this, LanService::class.java).setAction("STOP_LAN"), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val openIntent = PendingIntent.getActivity(this, 312, Intent(this, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, "mcm_lan") else Notification.Builder(this)
        val notification = builder.setContentTitle("Minh Cảnh Mobile • Kết nối máy tính").setContentText(intent?.getStringExtra("address") ?: "Đang chia sẻ dữ liệu trong mạng cửa hàng").setSmallIcon(android.R.drawable.stat_notify_sync).setContentIntent(openIntent).setOngoing(true).addAction(android.R.drawable.ic_media_pause, "Ngắt kết nối", stopIntent).build()
        if (Build.VERSION.SDK_INT >= 29) startForeground(311, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE) else startForeground(311, notification)
        if (wake == null) {
            wake = (getSystemService(POWER_SERVICE) as PowerManager).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "MinhCanh:LAN")
            wake?.acquire()
        }
        return START_NOT_STICKY
    }
    override fun onDestroy() { if (wake?.isHeld == true) wake?.release(); wake = null; onStopRequested?.invoke(); super.onDestroy() }
}
''')
# Flutter requires every asset directory to be explicitly listed.
dest = Path('assets/desktop')
if dest.exists(): shutil.rmtree(dest)
shutil.copytree('build/web', dest)
pubspec = Path('pubspec.yaml')
s = pubspec.read_text()
asset_dirs = [dest] + sorted(p for p in dest.rglob('*') if p.is_dir())
s += '\n  assets:\n' + ''.join('    - ' + p.as_posix() + '/\n' for p in asset_dirs)
pubspec.write_text(s)
