package io.github.bluebubblesapp.bluebubbles

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Telephony
import android.util.Log
import com.klinker.android.send_message.MmsSentReceiver
import java.io.File

/** Keeps Android's MMS provider in sync with the carrier send result. */
class BlueBubblesMmsSentReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pendingResult = goAsync()
        val sendResult = resultCode
        Thread {
            try {
                intent.getStringExtra(MmsSentReceiver.EXTRA_CONTENT_URI)
                    ?.takeIf { it.isNotBlank() }
                    ?.let(Uri::parse)
                    ?.let { messageUri ->
                        val values = ContentValues(1).apply {
                            put(
                                Telephony.Mms.MESSAGE_BOX,
                                if (sendResult == Activity.RESULT_OK) {
                                    Telephony.Mms.MESSAGE_BOX_SENT
                                } else {
                                    Telephony.Mms.MESSAGE_BOX_FAILED
                                },
                            )
                        }
                        context.contentResolver.update(
                            messageUri,
                            values,
                            null,
                            null,
                        )
                    }
                intent.getStringExtra(MmsSentReceiver.EXTRA_FILE_PATH)
                    ?.takeIf { it.isNotBlank() }
                    ?.let(::File)
                    ?.delete()
                Log.i(
                    "BlueBubblesSms",
                    "MMS carrier result: $sendResult",
                )
            } catch (error: Exception) {
                Log.e(
                    "BlueBubblesSms",
                    "Could not store the MMS carrier result",
                    error,
                )
            } finally {
                pendingResult.finish()
            }
        }.start()
    }
}
