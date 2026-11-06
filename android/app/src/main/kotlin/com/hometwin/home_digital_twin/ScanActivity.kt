package com.hometwin.home_digital_twin

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PointF
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.opengl.Matrix
import android.os.Build
import android.text.InputType
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import com.google.ar.core.Config
import com.google.ar.core.DepthPoint
import com.google.ar.core.Frame
import com.google.ar.core.Plane
import com.google.ar.core.Session
import com.google.ar.core.TrackingState
import com.google.ar.core.ArCoreApk
import com.google.ar.core.exceptions.CameraNotAvailableException
import com.google.ar.core.exceptions.UnavailableUserDeclinedInstallationException
import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale
import java.util.concurrent.CopyOnWriteArrayList
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * ARCore room scanner.
 *
 * Flow:
 *  1. FLOOR   - user aims the centre crosshair at each floor corner of the room (wall/floor junction)
 *               and taps "Add corner", walking around the room in order.
 *  2. CEILING - user measures ceiling height (crosshair on ceiling) or types it.
 *  3. Result  - returned to Flutter as JSON (corners relative to corner #1, wall lengths, area, height).
 *
 * Coordinates: ARCore world space (metres, +Y up). Floor polygon uses (x, z).
 */
class ScanActivity : Activity(), GLSurfaceView.Renderer {

    private enum class Mode { FLOOR, CEILING }

    private var session: Session? = null
    private var installRequested = false
    private var permissionAsked = false
    private var depthOn = false

    private lateinit var glView: GLSurfaceView
    private lateinit var overlay: OverlayView
    private lateinit var status: TextView
    private lateinit var info: TextView
    private lateinit var btnA: Button
    private lateinit var btnB: Button
    private lateinit var btnC: Button

    private val bg = BackgroundRenderer()
    private var cameraTexSet = false
    private var viewportChanged = true
    private var w = 1
    private var h = 1

    @Volatile private var mode = Mode.FLOOR
    @Volatile private var floorY: Float? = null
    @Volatile private var ceilingHeight: Float? = null
    @Volatile private var addRequested = false
    @Volatile private var measureRequested = false
    private val corners = CopyOnWriteArrayList<FloatArray>() // world [x, y(floor), z]
    private var lastStatus = ""
    private lateinit var tipsOverlay: View
    private lateinit var stepLabel: TextView

    private val proj = FloatArray(16)
    private val viewM = FloatArray(16)
    private val vp = FloatArray(16)

    // ---------------------------------------------------------------- lifecycle

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        buildUi()
    }

    override fun onResume() {
        super.onResume()
        if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            if (!permissionAsked) {
                permissionAsked = true
                requestPermissions(arrayOf(Manifest.permission.CAMERA), 1)
            }
            return
        }
        if (session == null) {
            try {
                when (ArCoreApk.getInstance().requestInstall(this, !installRequested)) {
                    ArCoreApk.InstallStatus.INSTALL_REQUESTED -> {
                        installRequested = true
                        return
                    }
                    ArCoreApk.InstallStatus.INSTALLED -> Unit
                }
                session = createSession()
            } catch (e: UnavailableUserDeclinedInstallationException) {
                fail("Room scan needs 'Google Play Services for AR' to be installed")
                return
            } catch (e: Exception) {
                fail("Could not start AR: ${e.message ?: e.javaClass.simpleName}")
                return
            }
        }
        try {
            session?.resume()
        } catch (e: CameraNotAvailableException) {
            fail("The camera is in use by another app. Close it and try again")
            return
        }
        glView.onResume()
    }

    override fun onPause() {
        super.onPause()
        if (::glView.isInitialized) glView.onPause() // pause GL first, then session
        session?.pause()
    }

    override fun onDestroy() {
        session?.close()
        session = null
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (grantResults.isEmpty() || grantResults[0] != PackageManager.PERMISSION_GRANTED) {
            fail("Camera permission is required for room scan")
        }
        // On grant, onResume() runs next and continues the setup.
    }

    private fun createSession(): Session {
        val s = Session(this)
        val cfg = Config(s)
        cfg.planeFindingMode = Config.PlaneFindingMode.HORIZONTAL_AND_VERTICAL
        cfg.updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
        cfg.focusMode = Config.FocusMode.AUTO
        if (s.isDepthModeSupported(Config.DepthMode.AUTOMATIC)) {
            cfg.depthMode = Config.DepthMode.AUTOMATIC
            depthOn = true
        }
        s.configure(cfg)
        return s
    }

    private fun fail(msg: String) {
        setResult(RESULT_CANCELED, Intent().putExtra(EXTRA_ERROR, msg))
        finish()
    }

    // ---------------------------------------------------------------- renderer (GL thread)

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        GLES20.glClearColor(0f, 0f, 0f, 1f)
        bg.createOnGlThread()
        cameraTexSet = false
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        w = max(width, 1)
        h = max(height, 1)
        GLES20.glViewport(0, 0, width, height)
        viewportChanged = true
    }

    override fun onDrawFrame(gl: GL10?) {
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_DEPTH_BUFFER_BIT)
        val s = session ?: return
        try {
            if (!cameraTexSet) {
                s.setCameraTextureName(bg.textureId)
                cameraTexSet = true
            }
            if (viewportChanged) {
                @Suppress("DEPRECATION")
                val rot = windowManager.defaultDisplay.rotation
                s.setDisplayGeometry(rot, w, h)
                viewportChanged = false
            }
            val frame = s.update()
            bg.draw(frame)

            val cam = frame.camera
            val tracking = cam.trackingState == TrackingState.TRACKING
            cam.getProjectionMatrix(proj, 0, 0.05f, 50f)
            cam.getViewMatrix(viewM, 0)
            Matrix.multiplyMM(vp, 0, proj, 0, viewM, 0)

            var centerHit: FloatArray? = null
            val msg: String
            if (!tracking) {
                msg = "Move your phone slowly from side to side…"
            } else {
                centerHit = findHit(s, frame, w / 2f, h / 2f)
                handleActions(centerHit)
                msg = statusFor(s, centerHit)
            }
            if (msg != lastStatus) {
                lastStatus = msg
                runOnUiThread { status.text = msg }
            }
            overlay.set(buildOverlay(centerHit, tracking))
        } catch (e: Exception) {
            Log.w(TAG, "frame error", e)
        }
    }

    private fun statusFor(s: Session, centerHit: FloatArray?): String {
        if (mode == Mode.CEILING) {
            return if (ceilingHeight == null) "Point the crosshair at the ceiling, then tap 'Measure ceiling' (or type the height)"
            else "Ceiling height set. Tap 'Save scan'"
        }
        if (floorY == null && lowestUpPlaneY(s) == null) return "Looking for the floor — move the camera slowly over the ground"
        if (centerHit == null) return "Point the crosshair at the floor (at a wall corner)"
        return "Corner ${corners.size + 1}: crosshair is on the corner — tap 'Add corner'"
    }

    private fun lowestUpPlaneY(s: Session): Float? =
        s.getAllTrackables(Plane::class.java)
            .filter {
                it.trackingState == TrackingState.TRACKING && it.subsumedBy == null &&
                    it.type == Plane.Type.HORIZONTAL_UPWARD_FACING
            }
            .minOfOrNull { it.centerPose.ty() }

    /** Hit-test at screen (x, y). Returns world [x, y, z] if it is a valid point for the current mode. */
    private fun findHit(s: Session, frame: Frame, x: Float, y: Float): FloatArray? {
        val fy = floorY
        for (hit in frame.hitTest(x, y)) {
            val t = hit.trackable
            val p = hit.hitPose
            if (mode == Mode.FLOOR) {
                if (fy == null) {
                    // First corner: must be on the lowest upward plane (= floor, not a table).
                    if (t is Plane && t.type == Plane.Type.HORIZONTAL_UPWARD_FACING && t.isPoseInPolygon(p)) {
                        val low = lowestUpPlaneY(s)
                        if (low == null || p.ty() <= low + 0.3f) return floatArrayOf(p.tx(), p.ty(), p.tz())
                    }
                } else if (abs(p.ty() - fy) < 0.25f) {
                    val onFloor = t is Plane && t.type == Plane.Type.HORIZONTAL_UPWARD_FACING && t.isPoseInExtents(p)
                    if (onFloor || t is DepthPoint) return floatArrayOf(p.tx(), fy, p.tz())
                }
            } else {
                val hgt = p.ty() - (fy ?: 0f)
                val ceil = (t is Plane && t.type == Plane.Type.HORIZONTAL_DOWNWARD_FACING) || t is DepthPoint
                if (ceil && hgt in 1.8f..6f) return floatArrayOf(p.tx(), p.ty(), p.tz())
            }
        }
        return null
    }

    private fun handleActions(centerHit: FloatArray?) {
        if (addRequested) {
            addRequested = false
            if (mode == Mode.FLOOR) {
                val last = corners.lastOrNull()
                when {
                    centerHit == null -> toast("No floor found here. Point the crosshair at the ground, at a wall corner")
                    last != null && dist2d(last, centerHit) < 0.15f -> toast("This corner is too close to the previous corner")
                    else -> {
                        if (floorY == null) floorY = centerHit[1]
                        corners.add(centerHit)
                        uiRefresh()
                    }
                }
            }
        }
        if (measureRequested) {
            measureRequested = false
            if (mode == Mode.CEILING) {
                if (centerHit == null) {
                    toast("Ceiling not detected. Use 'Type height' to enter the height yourself")
                } else {
                    ceilingHeight = centerHit[1] - (floorY ?: 0f)
                    uiRefresh()
                }
            }
        }
    }

    // ---------------------------------------------------------------- overlay data

    private fun project(x: Float, y: Float, z: Float): PointF? {
        val o = FloatArray(4)
        Matrix.multiplyMV(o, 0, vp, 0, floatArrayOf(x, y, z, 1f), 0)
        if (o[3] <= 0.01f) return null // behind the camera
        val nx = o[0] / o[3]
        val ny = o[1] / o[3]
        return PointF((nx * 0.5f + 0.5f) * w, (1f - (ny * 0.5f + 0.5f)) * h)
    }

    private fun buildOverlay(centerHit: FloatArray?, tracking: Boolean): OverlayState {
        val n = corners.size
        val pts = corners.map { project(it[0], it[1], it[2]) }
        val labels = ArrayList<Pair<PointF, String>>()
        val closed = mode == Mode.CEILING && n >= 3
        val segs = if (closed) n else n - 1
        for (i in 0 until segs) {
            val a = corners[i]
            val b = corners[(i + 1) % n]
            val m = project((a[0] + b[0]) / 2f, a[1], (a[2] + b[2]) / 2f)
            if (m != null) labels.add(m to fmt(dist2d(a, b)) + " m")
        }
        var live: PointF? = null
        var liveLabel: String? = null
        if (mode == Mode.FLOOR && centerHit != null && n > 0) {
            live = project(centerHit[0], centerHit[1], centerHit[2])
            liveLabel = fmt(dist2d(corners.last(), centerHit)) + " m"
        }
        return OverlayState(pts, closed, labels, live, liveLabel, centerHit != null && tracking)
    }

    // ---------------------------------------------------------------- UI

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()

    private fun styled(text: String, primary: Boolean) = Button(this).apply {
        this.text = text
        isAllCaps = false
        textSize = 15f
        setTextColor(Color.WHITE)
        background = GradientDrawable().apply {
            cornerRadius = dp(14).toFloat()
            setColor(if (primary) 0xFF0B6BE6.toInt() else 0x55FFFFFF)
        }
    }

    private fun buildUi() {
        val root = FrameLayout(this)

        glView = GLSurfaceView(this).apply {
            preserveEGLContextOnPause = true
            setEGLContextClientVersion(2)
            setEGLConfigChooser(8, 8, 8, 8, 16, 0)
            setRenderer(this@ScanActivity)
            renderMode = GLSurfaceView.RENDERMODE_CONTINUOUSLY
            setWillNotDraw(false)
        }
        root.addView(glView, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))

        overlay = OverlayView(this)
        root.addView(overlay, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))

        val top = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(0x99000000.toInt())
            setPadding(dp(8), dp(28), dp(14), dp(10))
        }
        val topRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val close = TextView(this).apply {
            text = "✕"
            textSize = 22f
            setTextColor(Color.WHITE)
            setPadding(dp(12), dp(4), dp(16), dp(4))
            setOnClickListener { finish() }
        }
        stepLabel = TextView(this).apply {
            text = "STEP 1 OF 2 · FLOOR & WALLS"
            textSize = 11f
            setTextColor(0xFF6FB6FF.toInt())
            typeface = Typeface.DEFAULT_BOLD
        }
        status = TextView(this).apply {
            text = "Starting AR…"
            textSize = 14f
            setTextColor(Color.WHITE)
        }
        topRow.addView(close)
        val statusCol = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        statusCol.addView(stepLabel)
        statusCol.addView(status)
        topRow.addView(statusCol, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        top.addView(topRow)
        root.addView(top, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.TOP))

        val bottom = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(0xCC000000.toInt())
            setPadding(dp(14), dp(12), dp(14), dp(28))
        }
        info = TextView(this).apply {
            textSize = 14f
            setTextColor(Color.WHITE)
            setPadding(0, 0, 0, dp(10))
        }
        btnA = styled("Undo", false)
        btnB = styled("Add corner", true)
        btnC = styled("Next ▸", false)
        val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        fun lp(wt: Float) = LinearLayout.LayoutParams(0, dp(52), wt).apply { marginEnd = dp(8) }
        row.addView(btnA, lp(1f))
        row.addView(btnB, lp(2f))
        row.addView(btnC, lp(1f).apply { marginEnd = 0 })
        bottom.addView(info)
        bottom.addView(row)
        root.addView(bottom, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.BOTTOM))

        btnA.setOnClickListener {
            if (mode == Mode.FLOOR) {
                if (corners.isNotEmpty()) corners.removeAt(corners.size - 1)
                if (corners.isEmpty()) floorY = null
            } else {
                ceilingHeight = null
                mode = Mode.FLOOR
            }
            uiRefresh()
        }
        btnB.setOnClickListener {
            if (mode == Mode.FLOOR) addRequested = true
            else if (ceilingHeight == null) measureRequested = true
            else save()
        }
        btnC.setOnClickListener {
            if (mode == Mode.FLOOR) {
                if (corners.size >= 3) {
                    mode = Mode.CEILING
                    uiRefresh()
                }
            } else askHeight()
        }

        tipsOverlay = buildTipsOverlay(root)
        root.addView(tipsOverlay, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))

        setContentView(root)
        updateButtons()
        updateInfo()
    }

    /** One-time full-screen tutorial card shown before scanning starts. */
    private fun buildTipsOverlay(root: FrameLayout): View {
        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(0xEE121826.toInt())
            setPadding(dp(28), dp(36), dp(28), dp(28))
        }
        val title = TextView(this).apply {
            text = "Scan your room"
            textSize = 22f
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            setPadding(0, 0, 0, dp(16))
        }
        val tips = listOf(
            "📱  Move the camera slowly around the room",
            "📐  Scan the walls, corners, floor and ceiling",
            "➕  Walk to each corner and tap \"Add corner\"",
            "🔄  Cover all areas — walk the full room from different angles",
            "✅  We'll show your progress as you go",
        )
        for (t in tips) {
            card.addView(TextView(this).apply {
                text = t
                textSize = 15f
                setTextColor(0xFFE4E9F5.toInt())
                setPadding(0, dp(6), 0, dp(6))
            })
        }
        val start = styled("Start scanning", true).apply {
            setOnClickListener { root.removeView(tipsOverlay) }
        }
        card.addView(start, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(52)).apply { topMargin = dp(20) })
        val wrap = FrameLayout(this).apply {
            setBackgroundColor(0xB0000000.toInt())
            setPadding(dp(24), dp(80), dp(24), dp(80))
        }
        wrap.addView(card)
        return wrap
    }

    private fun uiRefresh() = runOnUiThread {
        updateButtons()
        updateInfo()
        if (::stepLabel.isInitialized) {
            stepLabel.text = if (mode == Mode.FLOOR) "STEP 1 OF 2 · WALK & TAP EACH CORNER" else "STEP 2 OF 2 · CEILING HEIGHT"
        }
    }

    private fun updateButtons() {
        val n = corners.size
        if (mode == Mode.FLOOR) {
            btnA.text = "Undo"; btnA.isEnabled = n > 0
            btnB.text = "Add corner"; btnB.isEnabled = true
            btnC.text = "Next ▸"; btnC.isEnabled = n >= 3
        } else {
            btnA.text = "◂ Back"; btnA.isEnabled = true
            btnB.text = if (ceilingHeight == null) "Measure ceiling" else "Save scan"; btnB.isEnabled = true
            btnC.text = "Type height"; btnC.isEnabled = true
        }
        for (b in listOf(btnA, btnB, btnC)) b.alpha = if (b.isEnabled) 1f else 0.4f
    }

    private fun updateInfo() {
        val n = corners.size
        info.text = if (mode == Mode.FLOOR) {
            if (n < 3) "Corners: $n  (at least 3 needed, add them walking around the room in one direction)"
            else "Corners: $n   Area: ${fmt(polyArea(corners.map { doubleArrayOf(it[0].toDouble(), it[2].toDouble()) }).toFloat())} m²"
        } else {
            val hh = ceilingHeight
            "Height: " + (if (hh == null) "—" else fmt(hh) + " m") +
                "   Area: ${fmt(polyArea(corners.map { doubleArrayOf(it[0].toDouble(), it[2].toDouble()) }).toFloat())} m²"
        }
    }

    private fun askHeight() {
        val et = EditText(this).apply {
            inputType = InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_FLAG_DECIMAL
            setText(String.format(Locale.US, "%.2f", ceilingHeight ?: 2.7f))
        }
        AlertDialog.Builder(this)
            .setTitle("Ceiling height (meters)")
            .setView(et)
            .setPositiveButton("OK") { _, _ ->
                val v = et.text.toString().replace(',', '.').toFloatOrNull()
                if (v == null || v < 1.8f || v > 6f) toast("Enter a value between 1.8 and 6 meters")
                else {
                    ceilingHeight = v
                    uiRefresh()
                }
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun toast(msg: String) = runOnUiThread { Toast.makeText(this, msg, Toast.LENGTH_SHORT).show() }

    // ---------------------------------------------------------------- result

    private fun save() {
        if (corners.size < 3 || ceilingHeight == null) return
        try {
            toast("Scan complete ✓ Building your 3D model…")
            setResult(RESULT_OK, Intent().putExtra(EXTRA_JSON, buildResult()))
            finish()
        } catch (e: Exception) {
            toast("Could not save scan: ${e.message}")
        }
    }

    private fun buildResult(): String {
        val c = corners.toList()
        val n = c.size
        // Re-origin at corner #1 and rotate so the first wall runs along +X.
        val ang = atan2((c[1][2] - c[0][2]).toDouble(), (c[1][0] - c[0][0]).toDouble())
        val ca = cos(-ang)
        val sa = sin(-ang)
        val pts = c.map {
            val dx = (it[0] - c[0][0]).toDouble()
            val dz = (it[2] - c[0][2]).toDouble()
            doubleArrayOf(dx * ca - dz * sa, dx * sa + dz * ca)
        }
        val walls = (0 until n).map { i ->
            val a = pts[i]
            val b = pts[(i + 1) % n]
            hypot(b[0] - a[0], b[1] - a[1])
        }
        val xs = pts.map { it[0] }
        val zs = pts.map { it[1] }
        val o = JSONObject()
        o.put("version", 1)
        o.put("unit", "m")
        o.put("corners", JSONArray(pts.map { JSONArray(listOf(r3(it[0]), r3(it[1]))) }))
        o.put("height", r3(ceilingHeight!!.toDouble()))
        o.put("area_m2", r3(polyArea(pts)))
        o.put("perimeter_m", r3(walls.sum()))
        o.put("width_m", r3(xs.max() - xs.min()))
        o.put("depth_m", r3(zs.max() - zs.min()))
        o.put("walls", JSONArray(walls.map { r3(it) }))
        o.put("depth_sensor", depthOn)
        o.put("device", Build.MODEL)
        o.put("captured_at", System.currentTimeMillis())
        return o.toString()
    }

    // ---------------------------------------------------------------- helpers

    private fun dist2d(a: FloatArray, b: FloatArray) = hypot((a[0] - b[0]).toDouble(), (a[2] - b[2]).toDouble()).toFloat()
    private fun fmt(v: Float) = String.format(Locale.US, "%.2f", v)
    private fun r3(v: Double) = Math.round(v * 1000.0) / 1000.0

    private fun polyArea(p: List<DoubleArray>): Double {
        var s = 0.0
        for (i in p.indices) {
            val a = p[i]
            val b = p[(i + 1) % p.size]
            s += a[0] * b[1] - b[0] * a[1]
        }
        return abs(s) / 2.0
    }

    // ---------------------------------------------------------------- overlay view

    private class OverlayState(
        val pts: List<PointF?>,
        val closed: Boolean,
        val labels: List<Pair<PointF, String>>,
        val live: PointF?,
        val liveLabel: String?,
        val centerValid: Boolean,
    )

    private class OverlayView(ctx: Context) : View(ctx) {
        @Volatile private var st: OverlayState? = null

        private val line = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFF2D9CFF.toInt(); style = Paint.Style.STROKE; strokeWidth = 6f }
        private val liveLine = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xAAFFFFFF.toInt(); style = Paint.Style.STROKE; strokeWidth = 4f }
        private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0x442D9CFF; style = Paint.Style.FILL }
        private val dot = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE; style = Paint.Style.FILL }
        private val dotRing = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFF0B6BE6.toInt(); style = Paint.Style.STROKE; strokeWidth = 5f }
        private val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE; textSize = 36f; typeface = Typeface.DEFAULT_BOLD; textAlign = Paint.Align.CENTER
            setShadowLayer(6f, 0f, 0f, Color.BLACK)
        }
        private val cross = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeWidth = 5f }

        fun set(s: OverlayState) {
            st = s
            postInvalidate()
        }

        override fun onDraw(canvas: Canvas) {
            val s = st
            val cx = width / 2f
            val cy = height / 2f
            cross.color = if (s?.centerValid == true) 0xFF3DDC84.toInt() else 0xFFFFFFFF.toInt()
            canvas.drawCircle(cx, cy, 30f, cross)
            canvas.drawCircle(cx, cy, 4f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = cross.color })
            if (s == null) return

            val pts = s.pts
            if (s.closed && pts.size >= 3 && pts.all { it != null }) {
                val path = Path()
                pts.forEachIndexed { i, p -> if (i == 0) path.moveTo(p!!.x, p.y) else path.lineTo(p!!.x, p.y) }
                path.close()
                canvas.drawPath(path, fill)
            }
            val segs = if (s.closed) pts.size else pts.size - 1
            for (i in 0 until segs) {
                val a = pts[i]
                val b = pts[(i + 1) % pts.size]
                if (a != null && b != null) canvas.drawLine(a.x, a.y, b.x, b.y, line)
            }
            val last = pts.lastOrNull()
            if (s.live != null && last != null) canvas.drawLine(last.x, last.y, s.live.x, s.live.y, liveLine)
            for ((p, t) in s.labels) canvas.drawText(t, p.x, p.y - 18f, text)
            if (s.live != null && s.liveLabel != null) canvas.drawText(s.liveLabel, cx, cy - 56f, text)
            for (p in pts) if (p != null) {
                canvas.drawCircle(p.x, p.y, 14f, dot)
                canvas.drawCircle(p.x, p.y, 14f, dotRing)
            }
        }
    }

    companion object {
        const val EXTRA_JSON = "json"
        const val EXTRA_ERROR = "error"
        private const val TAG = "RoomScan"
    }
}