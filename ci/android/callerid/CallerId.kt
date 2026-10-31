package com.receiptapp.callerid

import android.annotation.TargetApi
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteException
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.telecom.Call
import android.telecom.CallScreeningService
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView

// =====================================================================
// شناسایی تماس ورودی مشتریان تعمیرگاه
//
// قواعد این بخش:
//  - فقط دیتابیس خود برنامه (receipt_app.db) و فقط به‌صورت «فقط‌خواندنی» باز می‌شود.
//  - هیچ‌جا مخاطبین گوشی خوانده، ذخیره یا تغییر داده نمی‌شود.
//  - هیچ داده‌ای در جایی نوشته نمی‌شود و شبکه استفاده نمی‌شود.
// =====================================================================

/** یکسان‌سازی شماره برای مقایسه‌ی دقیق (۰۹۱۲… = +98912… = 98912… = ۰۹۱۲… فارسی). */
object PhoneNumber {
    /** شماره‌ی استاندارد ۱۰ رقمی بدون صفر اول؛ اگر شماره معتبر نباشد null. */
    fun canonical(raw: String?): String? {
        if (raw == null) return null
        val sb = StringBuilder()
        for (ch in raw) {
            when (ch) {
                in '0'..'9' -> sb.append(ch)
                in '\u06F0'..'\u06F9' -> sb.append('0' + (ch - '\u06F0'))
                in '\u0660'..'\u0669' -> sb.append('0' + (ch - '\u0660'))
                else -> Unit
            }
        }
        val d = sb.toString()
        val n = when {
            d.length == 14 && d.startsWith("0098") -> d.substring(4)
            d.length == 12 && d.startsWith("98") -> d.substring(2)
            d.length == 11 && d.startsWith("0") -> d.substring(1)
            else -> d
        }
        return if (n.length == 10) n else null
    }
}

data class VehicleInfo(val brand: String, val model: String, val plate: String)

data class CustomerMatch(val name: String, val vehicles: List<VehicleInfo>)

/** جستجوی مشتری بر اساس شماره در دیتابیس محلی برنامه (فقط خواندنی). */
object CustomerLookup {
    private const val DB_NAME = "receipt_app.db"

    const val SQL_CUSTOMERS = "SELECT id, name, mobile FROM customers WHERE is_deleted = 0"
    const val SQL_VEHICLES = "SELECT b.name, m.name, v.plate_number FROM vehicles v LEFT JOIN vehicle_brands b ON b.id = v.brand_id LEFT JOIN vehicle_models m ON m.id = v.model_id WHERE v.is_deleted = 0 AND v.customer_id = ? ORDER BY v.created_at DESC"

    fun find(context: Context, incomingRaw: String?): List<CustomerMatch> {
        val key = PhoneNumber.canonical(incomingRaw) ?: return emptyList()
        val file = context.getDatabasePath(DB_NAME)
        if (!file.exists()) return emptyList()
        var attempt = 0
        while (attempt < 3) {
            try {
                return query(file.path, key)
            } catch (e: SQLiteException) {
                // معمولاً یعنی دیتابیس همان لحظه توسط خود برنامه در حال نوشتن است؛ دوباره تلاش می‌کنیم.
                attempt++
                if (attempt >= 3) return emptyList()
                try {
                    Thread.sleep(100)
                } catch (_: InterruptedException) {
                }
            } catch (e: Exception) {
                return emptyList()
            }
        }
        return emptyList()
    }

    private fun query(path: String, key: String): List<CustomerMatch> {
        val db = SQLiteDatabase.openDatabase(path, null, SQLiteDatabase.OPEN_READONLY)
        try {
            val ids = ArrayList<Long>()
            val names = ArrayList<String>()
            db.rawQuery(SQL_CUSTOMERS, null).use { c ->
                while (c.moveToNext()) {
                    if (PhoneNumber.canonical(c.getString(2)) == key) {
                        ids.add(c.getLong(0))
                        names.add(c.getString(1) ?: "")
                    }
                }
            }
            val out = ArrayList<CustomerMatch>()
            for (i in ids.indices) {
                val vehicles = ArrayList<VehicleInfo>()
                db.rawQuery(SQL_VEHICLES, arrayOf(ids[i].toString())).use { c ->
                    while (c.moveToNext()) {
                        vehicles.add(
                            VehicleInfo(
                                c.getString(0)?.trim() ?: "",
                                c.getString(1)?.trim() ?: "",
                                c.getString(2)?.trim() ?: ""
                            )
                        )
                    }
                }
                out.add(CustomerMatch(names[i].trim(), vehicles))
            }
            return out
        } finally {
            db.close()
        }
    }
}

/** پنجره‌ی شناور اطلاعات مشتری. با دکمه‌ی «بستن» یا بعد از ۲۵ ثانیه بسته می‌شود. */
object CallerOverlay {
    const val AUTO_CLOSE_MS = 25000L

    // فاصله‌ی پنجره از بالای صفحه (کسری از ارتفاع) تا روی دکمه‌های پاسخ/رد تماس نیفتد.
    private const val TOP_OFFSET_FRACTION = 0.20f
    private const val MATCH = ViewGroup.LayoutParams.MATCH_PARENT
    private const val WRAP = ViewGroup.LayoutParams.WRAP_CONTENT

    private val handler = Handler(Looper.getMainLooper())
    private var currentView: View? = null
    private var currentWm: WindowManager? = null
    private val autoClose = Runnable { dismiss() }

    private var regular: Typeface? = null
    private var boldFace: Typeface? = null
    private var fontsTried = false

    fun canDraw(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(context)

    /** true = پنجره نمایش داده شد (یا برای نمایش در صف قرار گرفت). */
    fun show(context: Context, number: String, matches: List<CustomerMatch>, isPreview: Boolean = false): Boolean {
        val app = context.applicationContext
        if (!canDraw(app)) return false
        if (Looper.myLooper() != Looper.getMainLooper()) {
            handler.post { show(app, number, matches, isPreview) }
            return true
        }
        dismiss()
        return try {
            val wm = app.getSystemService(Context.WINDOW_SERVICE) as WindowManager
            val view = buildView(app, number, matches, isPreview)
            wm.addView(view, layoutParams(app))
            currentView = view
            currentWm = wm
            handler.postDelayed(autoClose, AUTO_CLOSE_MS)
            true
        } catch (_: Throwable) {
            currentView = null
            currentWm = null
            false
        }
    }

    fun dismiss() {
        handler.removeCallbacks(autoClose)
        val v = currentView
        val wm = currentWm
        currentView = null
        currentWm = null
        if (v != null && wm != null) {
            try {
                wm.removeView(v)
            } catch (_: Throwable) {
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun layoutParams(ctx: Context): WindowManager.LayoutParams {
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            WindowManager.LayoutParams.TYPE_PHONE
        }
        // بدون فوکوس و بدون مسدود کردن لمس بیرون از کارت؛ تا پاسخ/رد تماس مختل نشود.
        val flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
        val lp = WindowManager.LayoutParams(MATCH, WRAP, type, flags, PixelFormat.TRANSLUCENT)
        lp.gravity = Gravity.TOP
        lp.y = (ctx.resources.displayMetrics.heightPixels * TOP_OFFSET_FRACTION).toInt()
        return lp
    }

    private fun dp(ctx: Context, v: Int): Int = (v * ctx.resources.displayMetrics.density + 0.5f).toInt()

    private fun fa(s: String): String {
        val sb = StringBuilder()
        for (ch in s) {
            if (ch in '0'..'9') sb.append('\u06F0' + (ch - '0')) else sb.append(ch)
        }
        return sb.toString()
    }

    private fun loadFont(ctx: Context, name: String): Typeface? = try {
        Typeface.createFromAsset(ctx.assets, "flutter_assets/assets/fonts/$name")
    } catch (_: Throwable) {
        null
    }

    private fun font(ctx: Context, bold: Boolean): Typeface? {
        if (!fontsTried) {
            fontsTried = true
            regular = loadFont(ctx, "Vazirmatn-Regular.ttf")
            boldFace = loadFont(ctx, "Vazirmatn-Bold.ttf")
        }
        return if (bold) (boldFace ?: regular) else regular
    }

    private fun text(ctx: Context, value: String, sizeSp: Float, color: Int, bold: Boolean = false): TextView {
        val t = TextView(ctx)
        t.text = value
        t.textSize = sizeSp
        t.setTextColor(color)
        t.layoutDirection = View.LAYOUT_DIRECTION_RTL
        t.textAlignment = View.TEXT_ALIGNMENT_VIEW_START
        val f = font(ctx, bold)
        if (f != null) {
            t.typeface = f
        } else if (bold) {
            t.setTypeface(null, Typeface.BOLD)
        }
        return t
    }

    private fun vehicleLabel(v: VehicleInfo): String {
        val parts = ArrayList<String>()
        val carName = (v.brand + " " + v.model).trim()
        if (carName.isNotEmpty()) parts.add(carName)
        if (v.plate.isNotEmpty()) parts.add("پلاک: " + v.plate)
        return if (parts.isEmpty()) "بدون مشخصات" else fa(parts.joinToString(" — "))
    }

    private fun displayNumber(number: String): String {
        val key = PhoneNumber.canonical(number)
        return fa(if (key != null) "0$key" else number)
    }

    private fun buildView(ctx: Context, number: String, matches: List<CustomerMatch>, preview: Boolean): View {
        val green = Color.parseColor("#1B6B45")
        val dark = Color.parseColor("#1C1B1F")
        val gray = Color.parseColor("#5F6368")

        val root = FrameLayout(ctx)
        root.layoutDirection = View.LAYOUT_DIRECTION_RTL
        root.setPadding(dp(ctx, 12), 0, dp(ctx, 12), 0)

        val card = LinearLayout(ctx)
        card.orientation = LinearLayout.VERTICAL
        card.layoutDirection = View.LAYOUT_DIRECTION_RTL
        card.setPadding(dp(ctx, 16), dp(ctx, 8), dp(ctx, 16), dp(ctx, 14))
        card.elevation = dp(ctx, 8).toFloat()
        val bg = GradientDrawable()
        bg.setColor(Color.WHITE)
        bg.cornerRadius = dp(ctx, 18).toFloat()
        bg.setStroke(dp(ctx, 2), green)
        card.background = bg
        root.addView(card, FrameLayout.LayoutParams(MATCH, WRAP))

        // سطر بالا: عنوان + دکمه‌ی بستن
        val header = LinearLayout(ctx)
        header.orientation = LinearLayout.HORIZONTAL
        header.layoutDirection = View.LAYOUT_DIRECTION_RTL
        header.gravity = Gravity.CENTER_VERTICAL
        val titleText = if (preview) "پیش‌نمایش (نمونه‌ی آزمایشی)" else "مشتری تعمیرگاه"
        header.addView(text(ctx, titleText, 13f, green, true), LinearLayout.LayoutParams(0, WRAP, 1f))
        val close = text(ctx, "بستن", 14f, green, true)
        close.setPadding(dp(ctx, 14), dp(ctx, 10), dp(ctx, 14), dp(ctx, 10))
        close.setOnClickListener { dismiss() }
        header.addView(close, LinearLayout.LayoutParams(WRAP, WRAP))
        card.addView(header, LinearLayout.LayoutParams(MATCH, WRAP))

        if (matches.size > 1) {
            card.addView(text(ctx, "چند مشتری با این شماره ثبت شده‌اند:", 13f, gray))
        }
        for (m in matches) {
            val name = text(ctx, if (m.name.isBlank()) "بدون نام" else m.name, 20f, dark, true)
            name.setPadding(0, dp(ctx, 4), 0, 0)
            card.addView(name)

            if (number.isNotBlank()) {
                card.addView(text(ctx, "شماره تماس: " + displayNumber(number), 14f, gray))
            }

            val count = m.vehicles.size
            when {
                count == 0 -> card.addView(text(ctx, "خودرویی ثبت نشده است", 14f, gray))
                count == 1 -> card.addView(text(ctx, "خودرو: " + vehicleLabel(m.vehicles[0]), 16f, dark))
                else -> {
                    val list = LinearLayout(ctx)
                    list.orientation = LinearLayout.VERTICAL
                    list.layoutDirection = View.LAYOUT_DIRECTION_RTL
                    list.visibility = View.GONE
                    for (v in m.vehicles) {
                        list.addView(text(ctx, "• " + vehicleLabel(v), 15f, dark))
                    }
                    val closedLabel = fa("$count خودرو ثبت شده — لمس برای مشاهده")
                    val openLabel = fa("$count خودرو — لمس برای بستن فهرست")
                    val summary = text(ctx, closedLabel, 15f, green, true)
                    summary.setPadding(0, dp(ctx, 6), 0, dp(ctx, 6))
                    summary.setOnClickListener {
                        val isOpen = list.visibility == View.VISIBLE
                        list.visibility = if (isOpen) View.GONE else View.VISIBLE
                        summary.text = if (isOpen) closedLabel else openLabel
                    }
                    card.addView(summary)
                    card.addView(list)
                }
            }
        }
        return root
    }
}

/**
 * سرویس شناسایی تماس. فقط وقتی سیستم تماس ورودی دارد آن را صدا می‌زند.
 * تماس همیشه بدون هیچ تغییری مجاز می‌شود (رد/بی‌صدا نمی‌شود)؛ این سرویس فقط اطلاعات نشان می‌دهد.
 */
@TargetApi(Build.VERSION_CODES.Q)
class CallerIdScreeningService : CallScreeningService() {
    override fun onScreenCall(callDetails: Call.Details) {
        try {
            if (callDetails.callDirection == Call.Details.DIRECTION_INCOMING) {
                val number = callDetails.handle?.schemeSpecificPart
                val matches = CustomerLookup.find(applicationContext, number)
                if (matches.isNotEmpty()) {
                    CallerOverlay.show(applicationContext, number ?: "", matches)
                }
            }
        } catch (_: Throwable) {
            // هر خطایی نباید تماس را مختل کند.
        } finally {
            respondToCall(callDetails, CallScreeningService.CallResponse.Builder().build())
        }
    }
}
