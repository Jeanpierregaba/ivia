import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_ui/ivia_ui.dart';

import 'orders_providers.dart';

/// Détail d'une commande (« Commande #1042 »).
class OrderScreen extends ConsumerWidget {
  const OrderScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = ref.watch(sellerOrderProvider(orderId)).value;
    return Scaffold(
      appBar: AppBar(
        title: Text(order == null ? 'Commande' : 'Commande #${order.number}'),
      ),
      body: const SizedBox.expand(),
      backgroundColor: IviaColors.background,
    );
  }
}
