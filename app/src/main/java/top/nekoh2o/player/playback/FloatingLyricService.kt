package top.nekoh2o.player.playback

import android.animation.ValueAnimator
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.PixelFormat
import android.graphics.Shader
import android.graphics.Typeface
import android.os.Build
import android.os.IBinder
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch
import top.nekoh2o.player.data.store.SettingsStore
import top.nekoh2o.player.ui.theme.CustomFont

/**
 * 悬浮窗歌词服务。
 *
 * - 主歌词行采用逐字卡拉OK渐变（[KaraokeTextView]）：已唱部分紫→蓝渐变、未唱半透明白，
 *   逐行独立填充（长句换行时第二行不会跟着第一行一起变色），并用属性动画平滑推进。
 * - 双行模式下第二行显示翻译；无翻译时兜底显示下一句歌词。
 * - 布局可拖动重新定位。
 *
 * 权限：SYSTEM_ALERT_WINDOW；UI 层在开启前已向用户说明原因。
 */
class FloatingLyricService : Service() {

    private var windowManager: WindowManager? = null
    private var container: LinearLayout? = null
    private var mainTv: KaraokeTextView? = null
    private var secondTv: TextView? = null
    private var layoutParams: WindowManager.LayoutParams? = null

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var collectJob: Job? = null

    // 拖动状态
    private var initialX = 0
    private var initialY = 0
    private var touchX = 0f
    private var touchY = 0f

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        addOverlay()
        startCollecting()
        FloatingLyricState.setEnabled(true)
    }

    private fun addOverlay() {
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        windowManager = wm

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            y = 200
        }
        layoutParams = params

        // 最大宽度取屏幕 92%，长句换行而非溢出/截断
        val maxW = (resources.displayMetrics.widthPixels * 0.92f).toInt()

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(0x66000000)
            setPadding(28, 10, 28, 10)
            gravity = Gravity.CENTER_HORIZONTAL
        }

        val main = KaraokeTextView(this).apply {
            setTextSizeSp(20f)
            setMaxWidthPx(maxW - 56) // 减去 padding
        }
        val second = TextView(this).apply {
            textSize = 15f
            setTextColor(0xFFE0E0E0.toInt())
            setShadowLayer(6f, 0f, 0f, 0xFF000000.toInt())
            maxWidth = maxW
            gravity = Gravity.CENTER_HORIZONTAL
            visibility = View.GONE
        }

        val customTypeface = CustomFont.loadTypeface(SettingsStore(this).load().customFontPath)
        if (customTypeface != null) {
            main.setTypeface(customTypeface)
            second.typeface = customTypeface
        }

        root.addView(main)
        root.addView(second)

        root.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = params.x; initialY = params.y
                    touchX = event.rawX; touchY = event.rawY
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    params.x = initialX + (event.rawX - touchX).toInt()
                    params.y = initialY + (event.rawY - touchY).toInt()
                    runCatching { wm.updateViewLayout(root, params) }
                    true
                }
                else -> false
            }
        }

        mainTv = main
        secondTv = second
        container = root

        runCatching { wm.addView(root, params) }
    }

    private fun startCollecting() {
        val settingsStore = SettingsStore(this)

        collectJob = scope.launch {
            // 主歌词 + 翻译 + 下一句 + 逐字进度
            combine(
                FloatingLyricState.lineFlow,
                FloatingLyricState.translationFlow,
                FloatingLyricState.nextLineFlow,
                FloatingLyricState.progressFlow
            ) { line, trans, next, progress -> LyricFrame(line, trans, next, progress) }
                .collectLatest { f ->
                    val cfg = settingsStore.load()
                    val showTrans = cfg.floatingLyricShowTranslation
                    val doubleRow = cfg.floatingLyricDoubleRow

                    mainTv?.setLine(f.line.ifBlank { "♪" }, f.progress)

                    secondTv?.let { tv ->
                        // 第二行内容：优先翻译，无翻译则用下一句兜底
                        val second = when {
                            showTrans && f.trans.isNotBlank() -> f.trans
                            f.next.isNotBlank() -> f.next
                            else -> ""
                        }
                        val visible = doubleRow && second.isNotBlank()
                        tv.visibility = if (visible) View.VISIBLE else View.GONE
                        if (visible) tv.text = second
                    }
                }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_STICKY

    override fun onDestroy() {
        collectJob?.cancel()
        mainTv?.release()
        container?.let { v -> runCatching { windowManager?.removeView(v) } }
        container = null
        mainTv = null
        secondTv = null
        FloatingLyricState.setEnabled(false)
        super.onDestroy()
    }

    private data class LyricFrame(
        val line: String, val trans: String, val next: String, val progress: Float
    )

    /**
     * 逐字卡拉OK歌词视图。
     *
     * 用 [StaticLayout] 排版，按行独立计算填充：先整体绘制未唱色，再对每一行
     * 裁剪出「已唱宽度」重绘紫→蓝渐变。填充进度用 [ValueAnimator] 平滑插值，
     * 消除 100ms 采样带来的跳变感。
     */
    class KaraokeTextView(context: Context) : View(context) {

        private val activeStart = 0xFFB388FF.toInt() // 紫
        private val activeEnd = 0xFF82B1FF.toInt()   // 蓝
        private val idleColor = 0xB3FFFFFF.toInt()   // 半透明白

        private val paint = TextPaint(TextPaint.ANTI_ALIAS_FLAG).apply {
            setShadowLayer(6f, 0f, 0f, 0xFF000000.toInt())
        }

        private var text: CharSequence = ""
        private var layout: StaticLayout? = null
        private var maxWidthPx: Int = 600

        private var targetFraction = 0f
        private var displayFraction = 0f
        private var animator: ValueAnimator? = null

        fun setTextSizeSp(sp: Float) {
            paint.textSize = sp * resources.displayMetrics.scaledDensity
            requestLayout(); invalidate()
        }

        fun setMaxWidthPx(px: Int) { maxWidthPx = px }

        fun setTypeface(typeface: Typeface?) {
            if (paint.typeface === typeface) return
            paint.typeface = typeface
            buildLayout()
            invalidate()
        }

        fun setLine(newText: CharSequence, fraction: Float) {
            val f = fraction.coerceIn(0f, 1f)
            if (newText != text) {
                text = newText
                buildLayout()
                // 换行/换句：直接对齐，避免从上一句进度回拉产生倒扫
                animator?.cancel()
                displayFraction = f
                targetFraction = f
                invalidate()
                return
            }
            animateTo(f)
        }

        private fun animateTo(f: Float) {
            if (f == targetFraction) return
            // 进度回退（seek 往回）直接跳，不做倒放动画
            if (f < displayFraction - 0.02f) {
                animator?.cancel()
                displayFraction = f; targetFraction = f
                invalidate(); return
            }
            targetFraction = f
            animator?.cancel()
            animator = ValueAnimator.ofFloat(displayFraction, f).apply {
                duration = 120L
                addUpdateListener {
                    displayFraction = it.animatedValue as Float
                    invalidate()
                }
                start()
            }
        }

        private fun buildLayout() {
            val desired = paint.measureText(text.toString()).toInt().coerceAtMost(maxWidthPx)
            val width = desired.coerceAtLeast(1)
            layout = StaticLayout.Builder
                .obtain(text, 0, text.length, paint, width)
                .setAlignment(Layout.Alignment.ALIGN_CENTER)
                .setIncludePad(true)
                .build()
            requestLayout()
        }

        override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
            val l = layout
            if (l == null) {
                setMeasuredDimension(1, (paint.textSize * 1.4f).toInt())
                return
            }
            val extra = (paint.textSize * 0.4f).toInt() // 阴影留白
            setMeasuredDimension(l.width, l.height + extra)
        }

        override fun onDraw(canvas: Canvas) {
            val l = layout ?: return
            val len = text.length.coerceAtLeast(1)
            val filledChars = displayFraction * len

            // 1) 整体未唱色
            paint.shader = null
            paint.color = idleColor
            l.draw(canvas)

            // 2) 逐行裁剪已唱部分，重绘渐变
            if (displayFraction <= 0f) return
            for (line in 0 until l.lineCount) {
                val lineStart = l.getLineStart(line)
                val lineEnd = l.getLineEnd(line)
                if (lineEnd <= lineStart) continue

                val top = l.getLineTop(line).toFloat()
                val bottom = l.getLineBottom(line).toFloat()

                // 该行左右边界（居中排版时行内有偏移）
                val lineLeft = l.getLineLeft(line)
                val lineRight = l.getLineRight(line)

                val fillX: Float = when {
                    filledChars >= lineEnd -> lineRight                 // 整行已唱
                    filledChars <= lineStart -> continue                 // 该行还没开始
                    else -> {
                        // 行内部分填充：按字符插值到精确 x
                        val whole = filledChars.toInt().coerceIn(lineStart, lineEnd)
                        val frac = filledChars - whole
                        val xWhole = l.getPrimaryHorizontal(whole)
                        val xNext = if (whole < lineEnd) l.getPrimaryHorizontal(whole + 1) else xWhole
                        xWhole + (xNext - xWhole) * frac
                    }
                }

                // 每行的渐变按本行文字宽度铺设，颜色不跨行
                paint.shader = LinearGradient(
                    lineLeft, 0f, lineRight, 0f,
                    intArrayOf(activeStart, activeEnd, activeStart),
                    floatArrayOf(0f, 0.5f, 1f), Shader.TileMode.CLAMP
                )
                paint.color = activeStart // shader 存在时 color 被忽略，仅兜底

                canvas.save()
                canvas.clipRect(lineLeft, top, fillX, bottom)
                l.draw(canvas)
                canvas.restore()
            }
        }

        fun release() { animator?.cancel(); animator = null }
    }
}
