package app.kinly.chat

import android.Manifest
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.PowerManager
import android.provider.MediaStore
import android.provider.Settings
import android.webkit.MimeTypeMap
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Android glue: keeps Wi-Fi multicast alive for mDNS, runs the foreground
 * service that keeps messages arriving in the background, and exposes the
 * battery-optimization prompt to Dart.
 */
// FlutterFragmentActivity is used instead of FlutterActivity so AndroidX
// BiometricPrompt has a FragmentActivity host for the app lock.
class MainActivity : FlutterFragmentActivity() {
    private var multicastLock: WifiManager.MulticastLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        acquireNetworkLocks()
        startKinlyService()
        requestNotificationPermission()
        requestLegacyStoragePermission()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AppLockChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestBatteryExemption" -> {
                    requestBatteryExemption()
                    result.success(null)
                }
                "isBatteryExempt" -> result.success(isBatteryExempt())
                "setBackgroundService" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    if (enabled) {
                        startKinlyService()
                    } else {
                        stopService(Intent(this, KinlyService::class.java))
                    }
                    result.success(null)
                }
                "canInstallPackages" -> result.success(canInstallPackages())
                "saveToDownloads" -> saveToDownloads(
                    call.argument<String>("path"),
                    call.argument<String>("name"),
                    result,
                )
                "installApk" -> installApk(
                    call.argument<String>("path"),
                    result,
                )
                "openUrl" -> {
                    val url = call.argument<String>("url")
                    if (url.isNullOrBlank()) {
                        result.error("bad_args", "url is required", null)
                    } else {
                        try {
                            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(null)
                        } catch (error: Exception) {
                            result.error("no_handler", error.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        multicastLock?.release()
        multicastLock = null
        wifiLock?.release()
        wifiLock = null
        super.onDestroy()
    }

    private fun acquireNetworkLocks() {
        val wifi = applicationContext.getSystemService(WIFI_SERVICE) as WifiManager
        if (multicastLock == null) {
            multicastLock = wifi.createMulticastLock("kinly-mdns").apply {
                setReferenceCounted(false)
                acquire()
            }
        }
        if (wifiLock == null) {
            @Suppress("DEPRECATION")
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                WifiManager.WIFI_MODE_FULL_LOW_LATENCY
            } else {
                WifiManager.WIFI_MODE_FULL_HIGH_PERF
            }
            wifiLock = wifi.createWifiLock(mode, "kinly-wifi").apply {
                setReferenceCounted(false)
                acquire()
            }
        }
    }

    private fun startKinlyService() {
        val intent = Intent(this, KinlyService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
    }

    private fun isBatteryExempt(): Boolean {
        val power = getSystemService(POWER_SERVICE) as PowerManager
        return power.isIgnoringBatteryOptimizations(packageName)
    }

    private fun requestBatteryExemption() {
        if (isBatteryExempt()) return
        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
            data = Uri.parse("package:$packageName")
        }
        try {
            startActivity(intent)
        } catch (_: Exception) {
            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
        }
    }

    private fun canInstallPackages(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return true
        return packageManager.canRequestPackageInstalls()
    }

    private fun installApk(path: String?, result: MethodChannel.Result) {
        if (path.isNullOrBlank()) {
            result.error("bad_args", "path is required", null)
            return
        }
        val file = File(path)
        if (!file.exists() || file.length() == 0L) {
            result.error("missing_file", "APK not found", null)
            return
        }
        if (!canInstallPackages()) {
            // Send the user to the system page; installing again will work.
            try {
                startActivity(
                    Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:$packageName"),
                    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
            } catch (_: Exception) {
                startActivity(
                    Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
            }
            result.error("install_permission", "Allow installing unknown apps", null)
            return
        }
        try {
            val uri = FileProvider.getUriForFile(
                this,
                "$packageName.updates",
                file,
            )
            val intent = Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            startActivity(intent)
            result.success(null)
        } catch (error: Exception) {
            result.error("install_failed", error.message, null)
        }
    }

    private fun requestLegacyStoragePermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) return
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.WRITE_EXTERNAL_STORAGE)
            == PackageManager.PERMISSION_GRANTED
        ) return
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
            REQ_LEGACY_STORAGE,
        )
    }

    private fun saveToDownloads(path: String?, name: String?, result: MethodChannel.Result) {
        if (path.isNullOrBlank()) {
            result.error("bad_args", "path is required", null)
            return
        }
        val source = File(path)
        if (!source.exists() || source.length() == 0L) {
            result.error("missing_file", "file not found", null)
            return
        }
        val displayName = sanitizeFileName(name?.takeIf { it.isNotBlank() } ?: source.name)
        try {
            val saved = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                copyToDownloadsQ(source, displayName)
            } else {
                copyToDownloadsLegacy(source, displayName)
            }
            result.success(saved.toString())
        } catch (error: Exception) {
            result.error("save_failed", error.message, null)
        }
    }

    private fun copyToDownloadsQ(source: File, displayName: String): Uri {
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, displayName)
            put(MediaStore.Downloads.MIME_TYPE, mimeTypeFor(displayName))
            put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + File.separator + "Kinly")
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val resolver = applicationContext.contentResolver
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("MediaStore insert failed")
        try {
            resolver.openOutputStream(uri).use { output ->
                requireNotNull(output) { "output stream failed" }
                source.inputStream().use { input -> input.copyTo(output) }
            }
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return uri
        } catch (error: Exception) {
            resolver.delete(uri, null, null)
            throw error
        }
    }

    private fun copyToDownloadsLegacy(source: File, displayName: String): Uri {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.WRITE_EXTERNAL_STORAGE)
            != PackageManager.PERMISSION_GRANTED
        ) {
            requestLegacyStoragePermission()
            throw IllegalStateException("storage permission required")
        }
        val downloads = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        val folder = File(downloads, "Kinly").apply { mkdirs() }
        val target = uniqueFile(folder, displayName)
        source.inputStream().use { input -> target.outputStream().use { output -> input.copyTo(output) } }
        return Uri.fromFile(target)
    }

    private fun uniqueFile(folder: File, displayName: String): File {
        var target = File(folder, displayName)
        if (!target.exists()) return target
        val dot = displayName.lastIndexOf('.')
        val stem = if (dot > 0) displayName.substring(0, dot) else displayName
        val extension = if (dot > 0) displayName.substring(dot) else ""
        var index = 1
        while (target.exists()) {
            target = File(folder, "$stem ($index)$extension")
            index += 1
        }
        return target
    }

    private fun sanitizeFileName(name: String): String {
        val cleaned = name.replace('/', '_').replace('\\', '_').replace('\u0000', '_').trim()
        return if (cleaned.isBlank()) "kinly-file" else cleaned.take(120)
    }

    private fun mimeTypeFor(name: String): String {
        val extension = name.substringAfterLast('.', "").lowercase()
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
            ?: "application/octet-stream"
    }

    private companion object {
        const val CHANNEL = "app.kinly.chat/system"
        const val REQ_LEGACY_STORAGE = 73
    }
}
