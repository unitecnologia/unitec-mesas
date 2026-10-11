package br.com.unitec.unitec_mesas

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val updaterChannelName = "br.com.unitec.unitec_mesas/updater"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updaterChannelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "canInstall" -> result.success(canInstallPackages())
                        "openInstallSettings" -> result.success(openInstallSettings())
                        "apkInfo" -> result.success(apkInfo(call.argument<String>("path").orEmpty()))
                        "installApk" -> result.success(installApk(call.argument<String>("path").orEmpty()))
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("UPDATER", e.message, null)
                }
            }
    }

    // ---- Atualização do APK (GitHub Release) -------------------------------

    /** Android 8+: o usuário precisa liberar "Permitir desta fonte" para este app. */
    private fun canInstallPackages(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O || packageManager.canRequestPackageInstalls()

    private fun openInstallSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val intent = Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:$packageName"),
        )
        startActivity(intent)
        return true
    }

    /** Pacote e versão do APK baixado (só instala se for este app e mais novo). */
    private fun apkInfo(path: String): Map<String, Any?>? {
        val file = File(path)
        if (!file.exists()) return null
        val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageArchiveInfo(path, PackageManager.PackageInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageArchiveInfo(path, 0)
        } ?: return null
        val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
        return mapOf(
            "packageName" to info.packageName,
            "versionCode" to code,
            "versionName" to info.versionName,
            "currentPackage" to packageName,
        )
    }

    /** Abre o instalador padrão do Android (o usuário confirma a atualização). */
    private fun installApk(path: String): Boolean {
        val file = File(path)
        if (!file.exists() || file.length() == 0L) return false
        val uri = FileProvider.getUriForFile(
            this,
            "${applicationContext.packageName}.fileprovider",
            file,
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
        return true
    }
}
