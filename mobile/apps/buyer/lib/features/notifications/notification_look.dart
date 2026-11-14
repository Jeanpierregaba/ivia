import 'package:flutter/material.dart';
import 'package:ivia_ui/ivia_ui.dart';

/// Icône et couleur selon le type de notification.
(IconData, Color) notificationLook(String kind) => switch (kind) {
  _ when kind.contains('cancel') || kind.contains('fail') => (
    Icons.cancel_outlined,
    IviaColors.error,
  ),
  _
      when kind.contains('paid') ||
          kind.contains('payment') ||
          kind.contains('refund') =>
    (Icons.payments_outlined, IviaColors.success),
  _ when kind.contains('ready') || kind.contains('delivered') => (
    Icons.check_circle_outline,
    IviaColors.success,
  ),
  _ when kind.contains('pharmacy') => (
    Icons.local_pharmacy_outlined,
    IviaColors.secondary,
  ),
  _ => (Icons.notifications_rounded, IviaColors.secondary),
};
