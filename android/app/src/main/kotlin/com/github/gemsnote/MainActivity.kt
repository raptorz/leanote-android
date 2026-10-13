package com.github.gemsnote

import android.content.Intent
import android.os.Bundle
import android.net.Uri
import android.provider.OpenableColumns
import androidx.core.content.IntentCompat
import java.lang.ref.WeakReference
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.atomic.AtomicReference
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        private val readers = Executors.newFixedThreadPool(2)
        private val timeouts = Executors.newSingleThreadScheduledExecutor()
        private val activeReaders = AtomicInteger(0)
        private var activeActivity = WeakReference<MainActivity>(null)
        private val textTypes = setOf("text/plain", "text/markdown")
        private var resourceStore: SharedResourceStore? = null
    }

    private data class TextInput(val title: String, val text: String,
        val id: String = UUID.randomUUID().toString().replace("-", "").take(24),
        val kind: String = "", val size: Long = 0)
    private var shareChannel: MethodChannel? = null
    private val prefs by lazy { getSharedPreferences("shared_text_inbox", MODE_PRIVATE) }
    private fun resources(): SharedResourceStore = synchronized(MainActivity::class.java) {
        resourceStore ?: SharedResourceStore(File(applicationContext.filesDir, "shared_resources")).also { resourceStore = it }
    }

    private fun pruneResources(queue: JSONArray) {
        resources().prune((0 until queue.length()).map { queue.getJSONObject(it).getString("id") }.toSet())
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        activeActivity = WeakReference(this)
        shareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "gemsnote/shared_text")
        try { pruneResources(JSONArray(prefs.getString("queue", "[]"))) } catch (error: Exception) { showShareError(error) }
        shareChannel!!.setMethodCallHandler { call, result ->
            try {
                val queue = JSONArray(prefs.getString("queue", "[]"))
                when (call.method) {
                    "peek" -> {
                        if (queue.length() == 0) result.success(null)
                        else {
                            val item = queue.getJSONObject(0)
                            result.success(mapOf(
                                "id" to item.getString("id"),
                                "title" to item.getString("title"),
                                "text" to item.getString("text"),
                                "resourceKind" to item.optString("resourceKind", ""),
                                "resourceName" to item.optString("resourceName", ""),
                                "resourceSize" to item.optLong("resourceSize", 0),
                                "accountKey" to item.optString("accountKey", "")
                            ))
                        }
                    }
                    "claim" -> {
                        val id = call.argument<String>("id")
                        val account = call.argument<String>("accountKey")
                        val item = (0 until queue.length()).map { queue.getJSONObject(it) }
                            .firstOrNull { it.getString("id") == id }
                            ?: error("分享已不存在")
                        require(!account.isNullOrBlank())
                        val previous = item.optString("accountKey", "")
                        check(previous.isEmpty() || previous == account) { "此分享已指定其他账号" }
                        item.put("accountKey", account)
                        check(prefs.edit().putString("queue", queue.toString()).commit()) { "无法保存分享状态" }
                        result.success(null)
                    }
                    "acknowledge" -> {
                        val id = call.argument<String>("id")
                        require(!id.isNullOrBlank())
                        val remaining = JSONArray()
                        for (i in 0 until queue.length()) {
                            val item = queue.getJSONObject(i)
                            if (item.getString("id") != id) remaining.put(item)
                        }
                        check(prefs.edit().putString("queue", remaining.toString()).commit()) { "无法清除分享状态" }
                        resources().delete(id)
                        result.success(null)
                    }
                    "readResource" -> {
                        val id = call.argument<String>("id")
                        val account = call.argument<String>("accountKey")
                        val item = (0 until queue.length()).map { queue.getJSONObject(it) }
                            .firstOrNull { it.getString("id") == id } ?: error("分享已不存在")
                        require(!account.isNullOrBlank() && item.optString("accountKey") == account) { "此分享尚未指定当前账号" }
                        require(item.optString("resourceKind").isNotEmpty()) { "分享不包含资源文件" }
                        val size = item.getLong("resourceSize")
                        readers.execute {
                            try {
                                val bytes = resources().read(id, size)
                                runOnUiThread { result.success(bytes) }
                            } catch (error: Exception) {
                                runOnUiThread { result.error("shareResource", error.message, null) }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("shareInbox", error.message, null)
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) receiveText(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        receiveText(intent)
    }

    private fun receiveText(incoming: Intent?) {
        if (incoming == null || incoming.action !in setOf(Intent.ACTION_SEND, Intent.ACTION_SEND_MULTIPLE)) return
        try {
            require(incoming.type?.contains('/') == true) { "无法识别分享类型" }
            val multiple = incoming.action == Intent.ACTION_SEND_MULTIPLE
            val streams = if (multiple) {
                IntentCompat.getParcelableArrayListExtra(incoming, Intent.EXTRA_STREAM, Uri::class.java)?.toList()
                    ?: emptyList()
            } else {
                listOfNotNull(IntentCompat.getParcelableExtra(incoming, Intent.EXTRA_STREAM, Uri::class.java))
            }
            val clip = incoming.clipData
            require(clip == null || clip.itemCount <= 8) { "每次最多接收 8 项分享" }
            val clipUris = if (clip == null) emptyList() else
                (0 until clip.itemCount).mapNotNull { clip.getItemAt(it).uri }
            val uris = if (streams.isNotEmpty()) streams else clipUris
            val subject = SharedTextDecoder.title(incoming.getStringExtra(Intent.EXTRA_SUBJECT))
            @Suppress("DEPRECATION")
            val extraText = incoming.extras?.get(Intent.EXTRA_TEXT)
            val values = when (extraText) {
                null -> emptyList()
                is CharSequence -> listOf(extraText.toString())
                is ArrayList<*> -> extraText.map {
                    require(it is CharSequence) { "无法识别分享文本" }
                    it.toString()
                }
                else -> error("无法识别分享文本")
            }
            require(values.size <= 8) { "每次最多接收 8 项分享" }
            val texts = values.map { TextInput(subject, SharedTextDecoder.validate(it)) }
            require(multiple || uris.size <= 1 && texts.size <= 1) { "单项分享包含多项内容" }
            require(uris.size + texts.size in 1..8) { "每次需要分享 1–8 项文本或文本文件" }
            if (uris.isNotEmpty()) {
                require(multiple || uris.size == 1) { "单项分享包含多个文件，请使用多项分享" }
                require(uris.size <= 8) { "每次最多接收 8 项分享" }
                require(clipUris.all { it in uris }) { "分享包含未识别的额外文件" }
                readTextFiles(uris, subject, texts, incoming.type!!)
            } else {
                require(!incoming.hasExtra(Intent.EXTRA_STREAM)) { "无法识别分享文件" }
                enqueue(texts)
            }
        } catch (error: Exception) {
            showShareError(error)
        } finally {
            // The durable inbox owns accepted content, not the Activity intent.
            setIntent(Intent(this, MainActivity::class.java).setAction(Intent.ACTION_MAIN))
        }
    }

    private fun readTextFiles(uris: List<Uri>, subject: String, captions: List<TextInput>, declaredType: String) {
        check(activeReaders.incrementAndGet() <= 2) {
            activeReaders.decrementAndGet()
            "正在读取其他分享，请稍后重试"
        }
        val completed = AtomicBoolean(false)
        val timeout = AtomicReference<ScheduledFuture<*>?>()
        readers.execute {
            val staged = mutableListOf<String>()
            try {
                val inputs = uris.map { uri ->
                    check(!completed.get()) { "分享读取已结束" }
                    require(uri.scheme == "content" && !uri.authority.isNullOrEmpty()) {
                        "分享文件必须使用授权的 content URI"
                    }
                    val provider = packageManager.resolveContentProvider(uri.authority!!, 0)
                    require(provider?.applicationInfo?.uid != applicationInfo.uid) {
                        "不能通过外部分享读取应用内部文件"
                    }
                    val mime = contentResolver.getType(uri) ?: declaredType
                    var name = subject
                    contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                        if (cursor.moveToFirst()) {
                            val column = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                            if (column >= 0) name = SharedTextDecoder.title(cursor.getString(column))
                        }
                    }
                    if (mime in textTypes) {
                        val text = contentResolver.openInputStream(uri)?.use { SharedTextDecoder.read(it) }
                            ?: error("无法读取分享文件")
                        TextInput(name, text)
                    } else {
                        name = name.replace('\\', '/').substringAfterLast('/').ifBlank { "shared-file" }
                        name = name.replace(Regex("[\\x00-\\x1f\\x7f]"), "").ifBlank { "shared-file" }
                        name = name.substring(0, name.offsetByCodePoints(0, minOf(120, name.codePointCount(0, name.length))))
                        if (name == "." || name == "..") name = "shared-file"
                        val input = TextInput(name, "分享的文件：$name", kind = if (mime in setOf("image/png", "image/jpeg")) "image" else "attachment")
                        val size = contentResolver.openInputStream(uri)?.use { resources().write(input.id, it) { completed.get() } }
                            ?: error("无法读取分享文件")
                        staged.add(input.id)
                        input.copy(size = size)
                    }
                } + captions
                runOnUiThread {
                    if (completed.compareAndSet(false, true)) {
                        timeout.get()?.cancel(false)
                        try {
                            enqueue(inputs)
                            staged.forEach { resources().release(it) }
                        } catch (error: Exception) {
                            // SharedPreferences can update memory before a disk
                            // commit reports failure. Keep any referenced bytes.
                            staged.forEach { resources().release(it) }
                            runCatching { pruneResources(JSONArray(prefs.getString("queue", "[]"))) }
                            showShareError(error)
                        }
                    } else {
                        staged.forEach { runCatching { resources().delete(it) } }
                    }
                }
            } catch (error: Exception) {
                staged.forEach { runCatching { resources().delete(it) } }
                runOnUiThread {
                    if (completed.compareAndSet(false, true)) {
                        timeout.get()?.cancel(false)
                        showShareError(error)
                    }
                }
            } finally {
                activeReaders.decrementAndGet()
            }
        }
        timeout.set(timeouts.schedule({
            if (completed.compareAndSet(false, true)) {
                runOnUiThread { showShareError(IllegalStateException("读取分享超时，未保存，请重试")) }
            }
        }, 15, TimeUnit.SECONDS))
        if (completed.get()) timeout.get()?.cancel(false)
        // A provider may ignore cancellation. Keep its worker slot occupied
        // until I/O returns; timed-out results can never enter the inbox.
    }

    // Queue mutation and Flutter callbacks run on the main thread, including
    // file batches. Read the latest queue after I/O to preserve concurrent claims.
    private fun enqueue(inputs: List<TextInput>) {
        val queue = JSONArray(prefs.getString("queue", "[]"))
        pruneResources(queue)
        check(queue.length() + inputs.size <= 8) { "待处理分享容量不足，请先处理应用中的分享" }
        for (input in inputs) {
            queue.put(JSONObject().put("id", input.id)
                .put("title", input.title).put("text", input.text)
                .put("resourceKind", input.kind).put("resourceName", if (input.kind.isEmpty()) "" else input.title)
                .put("resourceSize", input.size))
        }
        check(prefs.edit().putString("queue", queue.toString()).commit()) { "无法保存分享内容" }
        // Persistence already succeeded. A detached engine or toast failure
        // must not cause callers to delete the newly committed originals.
        runCatching { activeActivity.get()?.shareChannel?.invokeMethod("changed", null) }
        runCatching { Toast.makeText(applicationContext, "已接收 ${inputs.size} 项分享，请在待处理分享中确认导入", Toast.LENGTH_LONG).show() }
    }

    private fun showShareError(error: Exception) {
        Toast.makeText(applicationContext, error.message ?: "无法读取分享内容", Toast.LENGTH_LONG).show()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        shareChannel?.setMethodCallHandler(null)
        shareChannel = null
        if (activeActivity.get() === this) activeActivity.clear()
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
