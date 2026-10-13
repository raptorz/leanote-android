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

class MainActivity : FlutterActivity() {
    companion object {
        private val readers = Executors.newFixedThreadPool(2)
        private val timeouts = Executors.newSingleThreadScheduledExecutor()
        private val activeReaders = AtomicInteger(0)
        private var activeActivity = WeakReference<MainActivity>(null)
        private val textTypes = setOf("text/plain", "text/markdown")
    }

    private data class TextInput(val title: String, val text: String)
    private var shareChannel: MethodChannel? = null
    private val prefs by lazy { getSharedPreferences("shared_text_inbox", MODE_PRIVATE) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        activeActivity = WeakReference(this)
        shareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "gemsnote/shared_text")
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
                        result.success(null)
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
            require(incoming.type in textTypes) { "目前只支持纯文本和 Markdown 分享" }
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
                readTextFiles(uris, subject, texts)
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

    private fun readTextFiles(uris: List<Uri>, subject: String, captions: List<TextInput>) {
        check(activeReaders.incrementAndGet() <= 2) {
            activeReaders.decrementAndGet()
            "正在读取其他分享，请稍后重试"
        }
        val completed = AtomicBoolean(false)
        val timeout = AtomicReference<ScheduledFuture<*>?>()
        readers.execute {
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
                    val mime = contentResolver.getType(uri)
                    require(mime == null || mime in textTypes) { "分享中包含非文本文件" }
                    var name = subject
                    contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                        if (cursor.moveToFirst()) {
                            val column = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                            if (column >= 0) name = SharedTextDecoder.title(cursor.getString(column))
                        }
                    }
                    val text = contentResolver.openInputStream(uri)?.use { SharedTextDecoder.read(it) }
                        ?: error("无法读取分享文件")
                    TextInput(name, text)
                } + captions
                runOnUiThread {
                    if (completed.compareAndSet(false, true)) {
                        timeout.get()?.cancel(false)
                        try { enqueue(inputs) } catch (error: Exception) { showShareError(error) }
                    }
                }
            } catch (error: Exception) {
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
        check(queue.length() + inputs.size <= 8) { "待处理分享容量不足，请先处理应用中的分享" }
        for (input in inputs) {
            queue.put(JSONObject().put("id", UUID.randomUUID().toString().replace("-", "").take(24))
                .put("title", input.title).put("text", input.text))
        }
        check(prefs.edit().putString("queue", queue.toString()).commit()) { "无法保存分享内容" }
        activeActivity.get()?.shareChannel?.invokeMethod("changed", null)
        Toast.makeText(applicationContext, "已接收 ${inputs.size} 项文本，请在待处理分享中确认导入", Toast.LENGTH_LONG).show()
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
