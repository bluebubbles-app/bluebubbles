package io.github.bluebubblesapp.bluebubbles

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony

class MmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.WAP_PUSH_DELIVER_ACTION) return
        val rawPdu = intent.getByteArrayExtra("data")
        if (rawPdu != null) {
            runCatching {
                context.openFileOutput(
                    "pending-mms-${System.currentTimeMillis()}.pdu",
                    Context.MODE_PRIVATE,
                ).use { it.write(rawPdu) }
            }
        }
        MessageNotifier.show(
            context,
            "MMS received",
            "MMS display is not available in this build yet.",
            enableActions = false,
        )
    }
}
