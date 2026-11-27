package app.kinly.chat

import android.app.KeyguardManager
import android.content.Context
import android.os.Build
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executor

/**
 * Bridges Android's BiometricPrompt to the Flutter app lock.
 *
 * Kinly never sees or stores biometric data or the device PIN. The prompt is
 * shown by Android and only a boolean result is returned to Dart. When the
 * device has no biometric hardware the prompt falls back to the device
 * credential (PIN, pattern or password) on API 30+.
 */
class AppLockChannel(
    private val activity: MainActivity,
    messenger: io.flutter.plugin.common.BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, CHANNEL)
    private var prompt: BiometricPrompt? = null

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "canAuthenticate" -> result.success(canAuthenticate())
            "isDeviceSecure" -> result.success(isDeviceSecure())
            "authenticate" -> {
                val title = call.argument<String>("title") ?: "Unlock Kinly"
                val subtitle = call.argument<String>("subtitle") ?: ""
                authenticate(title, subtitle, result)
            }
            else -> result.notImplemented()
        }
    }

    private fun canAuthenticate(): Boolean {
        val manager = BiometricManager.from(activity)
        val allowed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            BiometricManager.Authenticators.BIOMETRIC_STRONG or
                BiometricManager.Authenticators.DEVICE_CREDENTIAL
        } else {
            BiometricManager.Authenticators.BIOMETRIC_WEAK or
                BiometricManager.Authenticators.DEVICE_CREDENTIAL
        }
        return manager.canAuthenticate(allowed) == BiometricManager.BIOMETRIC_SUCCESS
    }

    private fun isDeviceSecure(): Boolean {
        val keyguard = activity.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        return keyguard.isDeviceSecure
    }

    private fun authenticate(
        title: String,
        subtitle: String,
        result: MethodChannel.Result,
    ) {
        if (!canAuthenticate()) {
            result.success(false)
            return
        }
        val executor: Executor = ContextCompat.getMainExecutor(activity)
        val callback = object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(authResult: BiometricPrompt.AuthenticationResult) {
                prompt = null
                result.success(true)
            }

            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                prompt = null
                result.success(false)
            }

            override fun onAuthenticationFailed() {
                // Keep the prompt open: the user can try again.
            }
        }
        val biometricPrompt = BiometricPrompt(activity, executor, callback)
        prompt = biometricPrompt
        val builder = BiometricPrompt.PromptInfo.Builder()
            .setTitle(title)
            .setAllowedAuthenticators(
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    BiometricManager.Authenticators.BIOMETRIC_STRONG or
                        BiometricManager.Authenticators.DEVICE_CREDENTIAL
                } else {
                    BiometricManager.Authenticators.BIOMETRIC_WEAK or
                        BiometricManager.Authenticators.DEVICE_CREDENTIAL
                },
            )
        if (subtitle.isNotEmpty()) builder.setSubtitle(subtitle)
        biometricPrompt.authenticate(builder.build())
    }

    private companion object {
        const val CHANNEL = "app.kinly.chat/lock"
    }
}
