import 'package:flutter/material.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

/// Discussion de la course (spec 037) : écrire au client ou à la boutique. Rien pour une course
/// pharmacie (pas de commande de boutique).
class MissionChatButtons extends StatelessWidget {
  const MissionChatButtons({super.key, required this.mission});
  final WorkMission mission;

  @override
  Widget build(BuildContext context) {
    final order = mission.orderId;
    if (order == null) return const SizedBox.shrink();
    Widget button(String label, IconData icon, ChatChannel c) => Expanded(
      child: OutlinedButton.icon(
        onPressed: () => openChat(context, c),
        icon: Icon(icon, size: 18),
        label: Text(label, overflow: TextOverflow.ellipsis),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(46),
          shape: const StadiumBorder(),
          foregroundColor: const Color(0xFF128C7E),
          side: const BorderSide(color: Color(0x55128C7E)),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: IviaSpacing.sm),
      child: Row(
        children: [
          button(
            'Écrire au client',
            Icons.chat_bubble_outline_rounded,
            ChatChannel.driverClient(order),
          ),
          const SizedBox(width: IviaSpacing.sm),
          button(
            'Écrire à la boutique',
            Icons.storefront_rounded,
            ChatChannel.driverShop(order),
          ),
        ],
      ),
    );
  }
}
