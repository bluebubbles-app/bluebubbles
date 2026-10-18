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
        // SmsManager documents RESULT_OK (-1) and positive MMS_ERROR_* values.
        // Some Android builds deliver RESULT_CANCELED (0) when the result metadata
        // is omitted even though the MMSC accepted the message. Zero is therefore
        // an indeterminate/successful hand-off, not a documented MMS failure.
        val carrierAccepted = sendResult <= Activity.RESULT_CANCELED
        Thread {
            try {
                intent.getStringExtra(MmsSentReceiver.EXTRA_CONTENT_URI)
                    ?.takeIf { it.isNotBlank() }
                    ?.let(Uri::parse)
                    ?.let { messageUri ->
                        val values = ContentValues(1).apply {
                            put(
                                Telephony.Mms.MESSAGE_BOX,
                                if (carrierAccepted) {
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
                    "MMS carrier result: $sendResult " +
                        "(${if (carrierAccepted) "accepted" else "failed"})",
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
