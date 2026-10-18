package io.github.bluebubblesapp.bluebubbles

import android.content.Context
import android.net.Uri
import android.provider.BaseColumns
import android.provider.Telephony
import android.util.Log
import com.google.android.mms.pdu_alt.PduHeaders
import com.klinker.android.send_message.MmsReceivedReceiver

class MmsReceiver : MmsReceivedReceiver() {
    override fun onMessageReceived(context: Context, messageUri: Uri) {
        runCatching {
            val details = readNotificationDetails(context, messageUri)
            MessageNotifier.show(
                context = context,
                address = details.address,
                body = details.preview,
                timestamp = details.timestamp,
                threadId = details.threadId,
                enableActions = details.address.isNotBlank(),
            )
            Log.i(TAG, "MMS downloaded and stored at $messageUri")
        }.onFailure { error ->
            Log.e(TAG, "MMS was stored but its notification could not be built", error)
        }
    }

    override fun onError(context: Context, error: String) {
        Log.e(TAG, "MMS download failed: $error")
    }

    private fun readNotificationDetails(
        context: Context,
        messageUri: Uri,
    ): MmsNotificationDetails {
        val messageId = messageUri.lastPathSegment.orEmpty()
        var threadId: Long? = null
        var timestamp = System.currentTimeMillis()
        context.contentResolver.query(
            messageUri,
            arrayOf(Telephony.Mms.THREAD_ID, Telephony.Mms.DATE),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                threadId = cursor.getLong(0).takeIf { it >= 0 }
                val providerDate = cursor.getLong(1)
                if (providerDate > 0) {
                    timestamp = if (providerDate < 10_000_000_000L) {
                        providerDate * 1_000L
                    } else {
                        providerDate
                    }
                }
            }
        }

        return MmsNotificationDetails(
            address = readSenderAddress(context, messageId),
            preview = readPreview(context, messageId),
            timestamp = timestamp,
            threadId = threadId,
        )
    }

    private fun readSenderAddress(context: Context, messageId: String): String {
        if (messageId.isBlank()) return ""
        val addressUri = Uri.parse("content://mms/$messageId/addr")
        return runCatching {
            context.contentResolver.query(
                addressUri,
                arrayOf("address", "type"),
                "type = ?",
                arrayOf(PduHeaders.FROM.toString()),
                null,
            )?.use { cursor ->
                while (cursor.moveToNext()) {
                    val value = cursor.getString(0)
                        ?.substringBefore("/TYPE=")
                        ?.trim()
                        .orEmpty()
                    if (value.isNotBlank() && value != "insert-address-token") {
                        return@use value
                    }
                }
                ""
            }.orEmpty()
        }.getOrDefault("")
    }

    private fun readPreview(context: Context, messageId: String): String {
        if (messageId.isBlank()) return "MMS"
        val textParts = mutableListOf<String>()
        var hasImage = false
        var hasAudio = false
        var hasVideo = false
        runCatching {
            context.contentResolver.query(
                Uri.parse("content://mms/part"),
                arrayOf(BaseColumns._ID, "ct", "text"),
                "mid = ?",
                arrayOf(messageId),
                null,
            )?.use { cursor ->
                while (cursor.moveToNext()) {
                    val contentType = cursor.getString(1).orEmpty()
                    when {
                        contentType == "text/plain" -> {
                            val inlineText = cursor.getString(2).orEmpty().trim()
                            if (inlineText.isNotEmpty()) textParts += inlineText
                        }
                        contentType.startsWith("image/") -> hasImage = true
                        contentType.startsWith("audio/") -> hasAudio = true
                        contentType.startsWith("video/") -> hasVideo = true
                    }
                }
            }
        }.onFailure { error ->
            Log.w(TAG, "Could not build the MMS notification preview", error)
        }
        return textParts.joinToString("\n").ifBlank {
            when {
                hasImage -> "Photo"
                hasAudio -> "Audio message"
                hasVideo -> "Video"
                else -> "MMS"
            }
        }
    }

    private data class MmsNotificationDetails(
        val address: String,
        val preview: String,
        val timestamp: Long,
        val threadId: Long?,
    )

    companion object {
        private const val TAG = "BlueBubblesMms"
    }
}
