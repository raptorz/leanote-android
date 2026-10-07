package com.github.gemsnote

import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

class MainActivity : FlutterActivity() {
    private var shareChannel: MethodChannel? = null
    private val prefs by lazy { getSharedPreferences("shared_text_inbox", MODE_PRIVATE) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
        if (incoming?.action != Intent.ACTION_SEND || incoming.type != "text/plain") return
        try {
            // Do not read streams, ClipData URIs, HTML or caller-provided IDs.
            val text = incoming.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
                ?: error("分享内容为空")
            require(text.isNotBlank() && !text.contains('\u0000')) { "分享内容必须是文本" }
            require(text.length <= 256 * 1024 && text.toByteArray(Charsets.UTF_8).size <= 256 * 1024) {
                "分享文本超过 256 KiB，请改用文件导入"
            }
            val title = incoming.getStringExtra(Intent.EXTRA_SUBJECT).orEmpty().take(200)
            val queue = JSONArray(prefs.getString("queue", "[]"))
            check(queue.length() < 8) { "待处理分享已满，请先处理应用中的分享" }
            queue.put(JSONObject().put("id", UUID.randomUUID().toString().replace("-", "").take(24))
                .put("title", title).put("text", text))
            check(prefs.edit().putString("queue", queue.toString()).commit()) { "无法保存分享内容" }
            shareChannel?.invokeMethod("changed", null)
            Toast.makeText(this, "已接收文本，登录后可在待处理分享中导入", Toast.LENGTH_LONG).show()
        } catch (error: Exception) {
            Toast.makeText(this, error.message ?: "无法读取分享内容", Toast.LENGTH_LONG).show()
        } finally {
            // Activity recreation must not enqueue the same intent again.
            setIntent(Intent(this, MainActivity::class.java).setAction(Intent.ACTION_MAIN))
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        shareChannel?.setMethodCallHandler(null)
        shareChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
