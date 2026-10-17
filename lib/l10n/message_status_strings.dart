import 'package:flutter/cupertino.dart';

import '../models/conversation.dart';

abstract final class MessageStatusStrings {
  static bool _isFrench(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'fr';

  static String label(BuildContext context, DeliveryState state) {
    final french = _isFrench(context);
    return switch (state) {
      DeliveryState.sending => french ? 'Envoi…' : 'Sending…',
      DeliveryState.sent => french ? 'Envoyé' : 'Sent',
      DeliveryState.delivered => french ? 'Distribué' : 'Delivered',
      DeliveryState.read => french ? 'Lu' : 'Read',
      DeliveryState.failed => french ? 'Non distribué' : 'Not Delivered',
    };
  }

  static String retryTitle(BuildContext context) =>
      _isFrench(context) ? 'Message non distribué' : 'Message Not Delivered';

  static String retryPrompt(BuildContext context) => _isFrench(context)
      ? 'Voulez-vous essayer de renvoyer ce message ?'
      : 'Would you like to try sending this message again?';

  static String cancel(BuildContext context) =>
      _isFrench(context) ? 'Annuler' : 'Cancel';

  static String retry(BuildContext context) =>
      _isFrench(context) ? 'Réessayer' : 'Try Again';
}
