package com.reignofplay.dutch

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import androidx.core.content.FileProvider
import java.io.File

object DutchDirectShareHandler {
    private const val AUTHORITY_SUFFIX = ".dutch_share"

    fun isAppInstalled(context: Context, packageName: String): Boolean {
        if (packageName.isEmpty()) return false
        return try {
            context.packageManager.getPackageInfo(packageName, 0)
            true
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }
    }

    fun resolveTikTokPackage(context: Context): String? {
        for (pkg in TIKTOK_PACKAGES) {
            if (isAppInstalled(context, pkg)) return pkg
        }
        return null
    }

    fun shareToApp(
        context: Context,
        packageName: String,
        filePath: String,
        mimeType: String,
        text: String?,
    ): String {
        if (!isAppInstalled(context, packageName)) {
            return "app_not_installed"
        }
        val file = File(filePath)
        if (!file.exists()) {
            return "error"
        }

        val authority = context.packageName + AUTHORITY_SUFFIX
        val contentUri: Uri = FileProvider.getUriForFile(context, authority, file)

        val intent = Intent(Intent.ACTION_SEND).apply {
            type = mimeType
            putExtra(Intent.EXTRA_STREAM, contentUri)
            if (!text.isNullOrEmpty()) {
                putExtra(Intent.EXTRA_TEXT, text)
            }
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            setPackage(packageName)
        }

        return try {
            context.startActivity(intent)
            "success"
        } catch (_: Exception) {
            "error"
        }
    }

    private val TIKTOK_PACKAGES = listOf(
        "com.zhiliaoapp.musically",
        "com.ss.android.ugc.trill",
    )
}
