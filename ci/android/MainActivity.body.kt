import android.annotation.TargetApi
import android.app.Activity
import android.app.role.RoleManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import com.receiptapp.callerid.CallerOverlay
import com.receiptapp.callerid.CustomerMatch
import com.receiptapp.callerid.VehicleInfo
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// خط package از فایل تولیدشده‌ی flutter create گرفته و بالای این فایل گذاشته می‌شود.
class MainActivity : FlutterActivity() {
    private val channelName = "receipt_app/caller_id"
    private val roleRequestCode = 4711
    private var pendingRoleResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> result.success(status())
                    "requestRole" -> requestRole(result)
                    "showPreview" -> result.success(showPreview())
                    else -> result.notImplemented()
                }
            }
    }

    private fun status(): Map<String, Any> {
        var roleAvailable = false
        var roleHeld = false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val state = roleStateQ()
            roleAvailable = state.first
            roleHeld = state.second
        }
        val contacts = checkCallingOrSelfPermission(android.Manifest.permission.READ_CONTACTS) ==
            PackageManager.PERMISSION_GRANTED
        return mapOf(
            "sdk" to Build.VERSION.SDK_INT,
            "roleAvailable" to roleAvailable,
            "roleHeld" to roleHeld,
            "overlayGranted" to CallerOverlay.canDraw(this),
            "contactsGranted" to contacts
        )
    }

    @TargetApi(Build.VERSION_CODES.Q)
    private fun roleStateQ(): Pair<Boolean, Boolean> {
        val rm = getSystemService(Context.ROLE_SERVICE) as? RoleManager ?: return Pair(false, false)
        val available = rm.isRoleAvailable(RoleManager.ROLE_CALL_SCREENING)
        val held = available && rm.isRoleHeld(RoleManager.ROLE_CALL_SCREENING)
        return Pair(available, held)
    }

    private fun requestRole(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.success(false)
            return
        }
        requestRoleQ(result)
    }

    @TargetApi(Build.VERSION_CODES.Q)
    private fun requestRoleQ(result: MethodChannel.Result) {
        val rm = getSystemService(Context.ROLE_SERVICE) as? RoleManager
        if (rm == null || !rm.isRoleAvailable(RoleManager.ROLE_CALL_SCREENING)) {
            result.success(false)
            return
        }
        if (rm.isRoleHeld(RoleManager.ROLE_CALL_SCREENING)) {
            result.success(true)
            return
        }
        if (pendingRoleResult != null) {
            result.error("busy", "role request already in progress", null)
            return
        }
        pendingRoleResult = result
        try {
            startActivityForResult(rm.createRequestRoleIntent(RoleManager.ROLE_CALL_SCREENING), roleRequestCode)
        } catch (e: Throwable) {
            pendingRoleResult = null
            result.success(false)
        }
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == roleRequestCode) {
            val r = pendingRoleResult
            pendingRoleResult = null
            r?.success(resultCode == Activity.RESULT_OK)
        }
    }

    /** پیش‌نمایش ظاهر پنجره با اطلاعات نمونه‌ی کاملاً مشخص‌شده (فقط برای تست ظاهر و مجوز نمایش). */
    private fun showPreview(): String {
        if (!CallerOverlay.canDraw(this)) return "no_overlay_permission"
        val sample = CustomerMatch(
            "نمونه‌ی آزمایشی",
            listOf(
                VehicleInfo("پژو", "206", "نمونه"),
                VehicleInfo("سمند", "LX", "")
            )
        )
        return if (CallerOverlay.show(this, "09120000000", listOf(sample), true)) "ok" else "failed"
    }
}
