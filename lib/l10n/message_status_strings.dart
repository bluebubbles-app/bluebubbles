import 'package:flutter/cupertino.dart';

import '../models/conversation.dart';

abstract final class MessageStatusStrings {
  static const supportedLocales = <Locale>[
    Locale('en'), Locale('fr'), Locale('de'), Locale('es'), Locale('it'),
    Locale('pt'), Locale('nl'), Locale('pl'), Locale('ru'), Locale('uk'),
    Locale('tr'), Locale('ar'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    Locale('ja'), Locale('ko'), Locale('hi'), Locale('id'), Locale('sv'),
    Locale('da'), Locale('nb'), Locale('fi'), Locale('cs'), Locale('ro'),
    Locale('el'), Locale('he'), Locale('th'), Locale('vi'),
  ];

  static const _newMessageTitles = <String, String>{
    'en': 'New Message', 'fr': 'Nouveau message',
    'de': 'Neue Nachricht', 'es': 'Nuevo mensaje',
    'it': 'Nuovo messaggio', 'pt': 'Nova mensagem',
    'nl': 'Nieuw bericht', 'pl': 'Nowa wiadomość',
    'ru': 'Новое сообщение', 'uk': 'Нове повідомлення',
    'tr': 'Yeni Mesaj', 'ar': 'رسالة جديدة',
    'zh_Hans': '新信息', 'zh_Hant': '新訊息',
    'ja': '新規メッセージ', 'ko': '새로운 메시지',
    'hi': 'नया संदेश', 'id': 'Pesan Baru',
    'sv': 'Nytt meddelande', 'da': 'Ny besked',
    'nb': 'Ny melding', 'fi': 'Uusi viesti',
    'cs': 'Nová zpráva', 'ro': 'Mesaj nou',
    'el': 'Νέο μήνυμα', 'he': 'הודעה חדשה',
    'th': 'ข้อความใหม่', 'vi': 'Tin nhắn mới',
  };

  static const _recipientLabels = <String, String>{
    'en': 'To:', 'fr': 'À :', 'de': 'An:', 'es': 'Para:', 'it': 'A:',
    'pt': 'Para:', 'nl': 'Aan:', 'pl': 'Do:', 'ru': 'Кому:',
    'uk': 'Кому:', 'tr': 'Kime:', 'ar': 'إلى:',
    'zh_Hans': '收件人:', 'zh_Hant': '收件人:', 'ja': '宛先:',
    'ko': '받는 사람:', 'hi': 'प्रति:', 'id': 'Kepada:', 'sv': 'Till:',
    'da': 'Til:', 'nb': 'Til:', 'fi': 'Vastaanottaja:', 'cs': 'Komu:',
    'ro': 'Către:', 'el': 'Προς:', 'he': 'אל:', 'th': 'ถึง:',
    'vi': 'Đến:',
  };

  static const _sendToTemplates = <String, String>{
    'en': 'Send to “{recipient}”', 'fr': 'Envoyer à « {recipient} »',
    'de': 'Senden an „{recipient}“', 'es': 'Enviar a “{recipient}”',
    'it': 'Invia a “{recipient}”', 'pt': 'Enviar para “{recipient}”',
    'nl': 'Stuur naar “{recipient}”', 'pl': 'Wyślij do „{recipient}”',
    'ru': 'Отправить «{recipient}»', 'uk': 'Надіслати «{recipient}»',
    'tr': '“{recipient}” kişisine gönder', 'ar': 'إرسال إلى «{recipient}»',
    'zh_Hans': '发送给“{recipient}”', 'zh_Hant': '傳送給「{recipient}」',
    'ja': '「{recipient}」に送信', 'ko': '“{recipient}”에게 보내기',
    'hi': '“{recipient}” को भेजें', 'id': 'Kirim ke “{recipient}”',
    'sv': 'Skicka till ”{recipient}”', 'da': 'Send til “{recipient}”',
    'nb': 'Send til «{recipient}»',
    'fi': 'Lähetä vastaanottajalle ”{recipient}”',
    'cs': 'Odeslat „{recipient}“', 'ro': 'Trimite către „{recipient}”',
    'el': 'Αποστολή σε «{recipient}»', 'he': 'שליחה אל „{recipient}”',
    'th': 'ส่งถึง “{recipient}”', 'vi': 'Gửi đến “{recipient}”',
  };

  static const _english = _MessageStatusCopy(
    sending: 'Sending…', sent: 'Sent', delivered: 'Delivered', read: 'Read',
    failed: 'Not Delivered', retryTitle: 'Message Not Delivered',
    retryPrompt: 'Would you like to try sending this message again?',
    cancel: 'Cancel', retry: 'Try Again',
  );

  static const _copies = <String, _MessageStatusCopy>{
    'en': _english,
    'fr': _MessageStatusCopy(
      sending: 'Envoi…', sent: 'Envoyé', delivered: 'Distribué', read: 'Lu',
      failed: 'Non distribué', retryTitle: 'Message non distribué',
      retryPrompt: 'Voulez-vous essayer de renvoyer ce message ?',
      cancel: 'Annuler', retry: 'Réessayer',
    ),
    'de': _MessageStatusCopy(
      sending: 'Wird gesendet…', sent: 'Gesendet', delivered: 'Zugestellt',
      read: 'Gelesen', failed: 'Nicht zugestellt',
      retryTitle: 'Nachricht nicht zugestellt',
      retryPrompt: 'Möchten Sie versuchen, diese Nachricht erneut zu senden?',
      cancel: 'Abbrechen', retry: 'Erneut versuchen',
    ),
    'es': _MessageStatusCopy(
      sending: 'Enviando…', sent: 'Enviado', delivered: 'Entregado',
      read: 'Leído', failed: 'No entregado',
      retryTitle: 'Mensaje no entregado',
      retryPrompt: '¿Quieres intentar enviar este mensaje de nuevo?',
      cancel: 'Cancelar', retry: 'Reintentar',
    ),
    'it': _MessageStatusCopy(
      sending: 'Invio…', sent: 'Inviato', delivered: 'Consegnato',
      read: 'Letto', failed: 'Non consegnato',
      retryTitle: 'Messaggio non consegnato',
      retryPrompt: 'Vuoi provare a inviare di nuovo questo messaggio?',
      cancel: 'Annulla', retry: 'Riprova',
    ),
    'pt': _MessageStatusCopy(
      sending: 'Enviando…', sent: 'Enviado', delivered: 'Entregue',
      read: 'Lido', failed: 'Não entregue',
      retryTitle: 'Mensagem não entregue',
      retryPrompt: 'Deseja tentar enviar esta mensagem novamente?',
      cancel: 'Cancelar', retry: 'Tentar novamente',
    ),
    'nl': _MessageStatusCopy(
      sending: 'Bezig met versturen…', sent: 'Verstuurd',
      delivered: 'Afgeleverd', read: 'Gelezen', failed: 'Niet afgeleverd',
      retryTitle: 'Bericht niet afgeleverd',
      retryPrompt: 'Wil je dit bericht opnieuw proberen te versturen?',
      cancel: 'Annuleren', retry: 'Opnieuw proberen',
    ),
    'pl': _MessageStatusCopy(
      sending: 'Wysyłanie…', sent: 'Wysłano', delivered: 'Dostarczono',
      read: 'Odczytano', failed: 'Niedostarczono',
      retryTitle: 'Wiadomość niedostarczona',
      retryPrompt: 'Czy spróbować wysłać tę wiadomość ponownie?',
      cancel: 'Anuluj', retry: 'Spróbuj ponownie',
    ),
    'ru': _MessageStatusCopy(
      sending: 'Отправка…', sent: 'Отправлено', delivered: 'Доставлено',
      read: 'Прочитано', failed: 'Не доставлено',
      retryTitle: 'Сообщение не доставлено',
      retryPrompt: 'Попробовать отправить это сообщение еще раз?',
      cancel: 'Отмена', retry: 'Повторить',
    ),
    'uk': _MessageStatusCopy(
      sending: 'Надсилання…', sent: 'Надіслано', delivered: 'Доставлено',
      read: 'Прочитано', failed: 'Не доставлено',
      retryTitle: 'Повідомлення не доставлено',
      retryPrompt: 'Спробувати надіслати це повідомлення ще раз?',
      cancel: 'Скасувати', retry: 'Повторити',
    ),
    'tr': _MessageStatusCopy(
      sending: 'Gönderiliyor…', sent: 'Gönderildi',
      delivered: 'Teslim edildi', read: 'Okundu', failed: 'Teslim edilmedi',
      retryTitle: 'Mesaj teslim edilmedi',
      retryPrompt: 'Bu mesajı yeniden göndermeyi denemek ister misiniz?',
      cancel: 'İptal', retry: 'Tekrar dene',
    ),
    'ar': _MessageStatusCopy(
      sending: 'جارٍ الإرسال…', sent: 'تم الإرسال', delivered: 'تم التسليم',
      read: 'تمت القراءة', failed: 'لم يتم التسليم',
      retryTitle: 'تعذر تسليم الرسالة',
      retryPrompt: 'هل تريد محاولة إرسال هذه الرسالة مرة أخرى؟',
      cancel: 'إلغاء', retry: 'إعادة المحاولة',
    ),
    'zh_Hans': _MessageStatusCopy(
      sending: '正在发送…', sent: '已发送', delivered: '已送达', read: '已读',
      failed: '未送达', retryTitle: '信息未送达',
      retryPrompt: '要再次尝试发送这条信息吗？', cancel: '取消', retry: '重试',
    ),
    'zh_Hant': _MessageStatusCopy(
      sending: '正在傳送…', sent: '已傳送', delivered: '已送達', read: '已讀',
      failed: '未送達', retryTitle: '訊息未送達',
      retryPrompt: '要再次嘗試傳送這則訊息嗎？', cancel: '取消', retry: '重試',
    ),
    'ja': _MessageStatusCopy(
      sending: '送信中…', sent: '送信済み', delivered: '配信済み',
      read: '開封済み', failed: '未配信', retryTitle: 'メッセージを配信できませんでした',
      retryPrompt: 'このメッセージをもう一度送信しますか？',
      cancel: 'キャンセル', retry: '再試行',
    ),
    'ko': _MessageStatusCopy(
      sending: '전송 중…', sent: '보냄', delivered: '전송됨', read: '읽음',
      failed: '전송되지 않음', retryTitle: '메시지가 전송되지 않음',
      retryPrompt: '이 메시지를 다시 보내시겠습니까?', cancel: '취소', retry: '다시 시도',
    ),
    'hi': _MessageStatusCopy(
      sending: 'भेजा जा रहा है…', sent: 'भेजा गया', delivered: 'डिलीवर हुआ',
      read: 'पढ़ा गया', failed: 'डिलीवर नहीं हुआ',
      retryTitle: 'संदेश डिलीवर नहीं हुआ',
      retryPrompt: 'क्या आप इस संदेश को फिर से भेजने की कोशिश करना चाहते हैं?',
      cancel: 'रद्द करें', retry: 'फिर कोशिश करें',
    ),
    'id': _MessageStatusCopy(
      sending: 'Mengirim…', sent: 'Terkirim', delivered: 'Disampaikan',
      read: 'Dibaca', failed: 'Tidak terkirim',
      retryTitle: 'Pesan tidak terkirim', retryPrompt: 'Coba kirim pesan ini lagi?',
      cancel: 'Batal', retry: 'Coba lagi',
    ),
    'sv': _MessageStatusCopy(
      sending: 'Skickar…', sent: 'Skickat', delivered: 'Levererat',
      read: 'Läst', failed: 'Inte levererat',
      retryTitle: 'Meddelandet levererades inte',
      retryPrompt: 'Vill du försöka skicka meddelandet igen?',
      cancel: 'Avbryt', retry: 'Försök igen',
    ),
    'da': _MessageStatusCopy(
      sending: 'Sender…', sent: 'Sendt', delivered: 'Leveret', read: 'Læst',
      failed: 'Ikke leveret', retryTitle: 'Beskeden blev ikke leveret',
      retryPrompt: 'Vil du prøve at sende beskeden igen?',
      cancel: 'Annuller', retry: 'Prøv igen',
    ),
    'nb': _MessageStatusCopy(
      sending: 'Sender…', sent: 'Sendt', delivered: 'Levert', read: 'Lest',
      failed: 'Ikke levert', retryTitle: 'Meldingen ble ikke levert',
      retryPrompt: 'Vil du prøve å sende meldingen på nytt?',
      cancel: 'Avbryt', retry: 'Prøv igjen',
    ),
    'fi': _MessageStatusCopy(
      sending: 'Lähetetään…', sent: 'Lähetetty', delivered: 'Toimitettu',
      read: 'Luettu', failed: 'Ei toimitettu',
      retryTitle: 'Viestiä ei toimitettu',
      retryPrompt: 'Haluatko yrittää lähettää viestin uudelleen?',
      cancel: 'Peruuta', retry: 'Yritä uudelleen',
    ),
    'cs': _MessageStatusCopy(
      sending: 'Odesílání…', sent: 'Odesláno', delivered: 'Doručeno',
      read: 'Přečteno', failed: 'Nedoručeno',
      retryTitle: 'Zpráva nebyla doručena',
      retryPrompt: 'Chcete zkusit odeslat zprávu znovu?',
      cancel: 'Zrušit', retry: 'Zkusit znovu',
    ),
    'ro': _MessageStatusCopy(
      sending: 'Se trimite…', sent: 'Trimis', delivered: 'Livrat',
      read: 'Citit', failed: 'Nelivrat', retryTitle: 'Mesaj nelivrat',
      retryPrompt: 'Doriți să încercați să trimiteți din nou acest mesaj?',
      cancel: 'Anulați', retry: 'Încercați din nou',
    ),
    'el': _MessageStatusCopy(
      sending: 'Αποστολή…', sent: 'Στάλθηκε', delivered: 'Παραδόθηκε',
      read: 'Διαβάστηκε', failed: 'Δεν παραδόθηκε',
      retryTitle: 'Το μήνυμα δεν παραδόθηκε',
      retryPrompt: 'Θέλετε να δοκιμάσετε να στείλετε ξανά αυτό το μήνυμα;',
      cancel: 'Ακύρωση', retry: 'Δοκιμάστε ξανά',
    ),
    'he': _MessageStatusCopy(
      sending: 'שולח…', sent: 'נשלח', delivered: 'נמסר', read: 'נקרא',
      failed: 'לא נמסר', retryTitle: 'ההודעה לא נמסרה',
      retryPrompt: 'לנסות לשלוח את ההודעה שוב?',
      cancel: 'ביטול', retry: 'ניסיון חוזר',
    ),
    'th': _MessageStatusCopy(
      sending: 'กำลังส่ง…', sent: 'ส่งแล้ว', delivered: 'ส่งถึงแล้ว',
      read: 'อ่านแล้ว', failed: 'ส่งไม่สำเร็จ', retryTitle: 'ส่งข้อความไม่สำเร็จ',
      retryPrompt: 'ต้องการลองส่งข้อความนี้อีกครั้งหรือไม่',
      cancel: 'ยกเลิก', retry: 'ลองอีกครั้ง',
    ),
    'vi': _MessageStatusCopy(
      sending: 'Đang gửi…', sent: 'Đã gửi', delivered: 'Đã chuyển',
      read: 'Đã đọc', failed: 'Chưa chuyển được',
      retryTitle: 'Tin nhắn chưa được chuyển',
      retryPrompt: 'Bạn có muốn thử gửi lại tin nhắn này không?',
      cancel: 'Hủy', retry: 'Thử lại',
    ),
  };

  static String _localeKey(BuildContext context) {
    final locale = Localizations.localeOf(context);
    if (locale.languageCode == 'zh') {
      final traditional = locale.scriptCode == 'Hant' ||
          const {'TW', 'HK', 'MO'}.contains(locale.countryCode);
      return traditional ? 'zh_Hant' : 'zh_Hans';
    }
    return locale.languageCode;
  }

  static _MessageStatusCopy _copy(BuildContext context) =>
      _copies[_localeKey(context)] ?? _english;

  static String label(BuildContext context, DeliveryState state) {
    final copy = _copy(context);
    return switch (state) {
      DeliveryState.sending => copy.sending,
      DeliveryState.sent => copy.sent,
      DeliveryState.delivered => copy.delivered,
      DeliveryState.read => copy.read,
      DeliveryState.failed => copy.failed,
    };
  }

  static String retryTitle(BuildContext context) => _copy(context).retryTitle;
  static String retryPrompt(BuildContext context) => _copy(context).retryPrompt;
  static String cancel(BuildContext context) => _copy(context).cancel;
  static String retry(BuildContext context) => _copy(context).retry;
  static String newMessage(BuildContext context) =>
      _newMessageTitles[_localeKey(context)] ?? _newMessageTitles['en']!;
  static String recipientLabel(BuildContext context) =>
      _recipientLabels[_localeKey(context)] ?? _recipientLabels['en']!;
  static String sendTo(BuildContext context, String recipient) =>
      (_sendToTemplates[_localeKey(context)] ?? _sendToTemplates['en']!)
          .replaceFirst('{recipient}', recipient);
}

class _MessageStatusCopy {
  const _MessageStatusCopy({
    required this.sending, required this.sent, required this.delivered,
    required this.read, required this.failed, required this.retryTitle,
    required this.retryPrompt, required this.cancel, required this.retry,
  });

  final String sending;
  final String sent;
  final String delivered;
  final String read;
  final String failed;
  final String retryTitle;
  final String retryPrompt;
  final String cancel;
  final String retry;
}
