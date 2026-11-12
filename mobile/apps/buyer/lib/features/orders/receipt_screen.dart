import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';
import 'package:share_plus/share_plus.dart';

import 'invoice.dart';

/// Ouvre le reçu dans l'app, avant tout téléchargement.
Future<void> showReceipt(BuildContext context, Invoice invoice) =>
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(builder: (_) => ReceiptScreen(invoice: invoice)),
    );

/// Reçu d'une commande ou d'une réservation : ticket aux bords en dents de
/// scie, puis « Partager » et « Télécharger » : une image du ticket, tel
/// qu'il est affiché.
class ReceiptScreen extends StatefulWidget {
  const ReceiptScreen({super.key, required this.invoice});

  final Invoice invoice;

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  var _busy = false;
  final _capture = GlobalKey();

  String get _file => 'recu-${widget.invoice.number}.png';

  /// Image PNG du ticket affiché, en haute définition.
  Future<Uint8List> _png() async {
    final boundary =
        _capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } catch (_) {
      showMessage(messenger, 'Impossible de préparer le reçu. Réessayez.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Partager : le téléphone propose WhatsApp, e-mail…
  Future<void> _share() => _run(() async {
    final file = XFile.fromData(
      await _png(),
      name: _file,
      mimeType: 'image/png',
    );
    await SharePlus.instance.share(
      ShareParams(files: [file], fileNameOverrides: [_file]),
    );
  });

  /// Télécharger : l'image va dans la galerie du téléphone (fichier
  /// téléchargé dans le navigateur).
  Future<void> _download() => _run(() async {
    final bytes = await _png();
    if (kIsWeb) {
      await XFile.fromData(
        bytes,
        name: _file,
        mimeType: 'image/png',
      ).saveTo(_file);
      return;
    }
    if (!await Gal.hasPermission() && !await Gal.requestPermission()) {
      if (mounted) {
        showMessage(
          ScaffoldMessenger.of(context),
          'Autorisez l’accès aux photos pour enregistrer le reçu.',
        );
      }
      return;
    }
    await Gal.putImageBytes(bytes, name: _file.replaceAll('.png', ''));
    if (mounted) {
      showIviaNotification(
        context,
        title: 'Reçu enregistré',
        body: 'Retrouvez-le dans vos photos.',
        icon: Icons.check_rounded,
        color: IviaColors.success,
      );
    }
  });

  @override
  Widget build(BuildContext context) {
    final brand = IviaAppBrand.of(context);
    return Scaffold(
      backgroundColor: IviaColors.berkeleyBlue,
      appBar: AppBar(
        backgroundColor: IviaColors.berkeleyBlue,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: Theme.of(context).textTheme.titleLarge
            ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
        title: Text(widget.invoice.isReceipt ? 'Reçu' : 'Récapitulatif'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  IviaSpacing.screen,
                  IviaSpacing.sm,
                  IviaSpacing.screen,
                  IviaSpacing.xl,
                ),
                child: IviaMaxWidth(
                  maxWidth: 480,
                  child: IviaReveal(
                    // Capturé tel quel pour l'image : ticket sur fond bleu.
                    child: RepaintBoundary(
                      key: _capture,
                      child: ColoredBox(
                        color: IviaColors.berkeleyBlue,
                        child: Padding(
                          padding: const EdgeInsets.all(IviaSpacing.lg),
                          child: _Ticket(invoice: widget.invoice),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                IviaSpacing.screen,
                0,
                IviaSpacing.screen,
                IviaSpacing.lg,
              ),
              child: IviaMaxWidth(
                maxWidth: 480,
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: IviaColors.berkeleyBlue,
                          disabledBackgroundColor: Colors.white70,
                        ),
                        onPressed: _busy ? null : _download,
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('Télécharger'),
                      ),
                    ),
                    const SizedBox(width: IviaSpacing.md),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: brand.action,
                        ),
                        onPressed: _busy ? null : _share,
                        icon: const Icon(Icons.ios_share_rounded),
                        label: const Text('Partager'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Le ticket : bords haut et bas en dents de scie.
class _Ticket extends StatelessWidget {
  const _Ticket({required this.invoice});

  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final brand = IviaAppBrand.of(context);
    final label = t.bodyMedium?.copyWith(color: IviaColors.secondary);
    final value = t.bodyLarge?.copyWith(
      color: IviaColors.text,
      fontWeight: FontWeight.w600,
    );
    Widget field(String title, String text) => Padding(
      padding: const EdgeInsets.only(bottom: IviaSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: label),
          const SizedBox(height: IviaSpacing.xs),
          Text(text, style: value),
        ],
      ),
    );
    Widget amount(String title, int xof, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: IviaSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(title, style: strong ? t.titleMedium : t.bodyMedium),
          ),
          Text(
            formatXof(xof),
            style: (strong ? t.titleLarge : t.bodyLarge)?.copyWith(
              fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
              color: strong ? brand.highlight : IviaColors.text,
            ),
          ),
        ],
      ),
    );
    final divider = Divider(color: IviaColors.border, height: IviaSpacing.xxl);
    return PhysicalShape(
      clipper: const _SawEdges(),
      color: IviaColors.surface,
      elevation: 6,
      shadowColor: Colors.black38,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          IviaSpacing.xxl,
          IviaSpacing.huge,
          IviaSpacing.xxl,
          IviaSpacing.huge,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IviaLogo(color: brand.logoOnLight, height: 34),
            const SizedBox(height: IviaSpacing.xl),
            Text(
              invoice.title,
              style: t.headlineSmall?.copyWith(
                color: IviaColors.berkeleyBlue,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: IviaSpacing.sm),
            Text(
              '${invoice.number}  ·  ${onDate(invoice.date)} à ${timeOfDay(invoice.date)}',
              style: t.titleSmall?.copyWith(
                color: IviaColors.secondary,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (!invoice.isReceipt) ...[
              const SizedBox(height: IviaSpacing.md),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: IviaColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: IviaSpacing.md,
                    vertical: IviaSpacing.xs,
                  ),
                  child: Text(
                    invoice.closedLabel!,
                    style: t.labelLarge?.copyWith(
                      color: IviaColors.error,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
            divider,
            field(
              'Vendu par',
              [
                invoice.seller,
                invoice.sellerAddress,
              ].where((s) => s.isNotEmpty).join('\n'),
            ),
            if (invoice.customer.isNotEmpty || invoice.customerPhone.isNotEmpty)
              field(
                'Client',
                [
                  invoice.customer,
                  invoice.customerPhone,
                ].where((s) => s.isNotEmpty).join('\n'),
              ),
            Text('Articles', style: label),
            const SizedBox(height: IviaSpacing.sm),
            for (final l in invoice.lines)
              Padding(
                padding: const EdgeInsets.only(bottom: IviaSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        '${l.quantity} × ${l.label}',
                        style: t.bodyMedium,
                      ),
                    ),
                    const SizedBox(width: IviaSpacing.md),
                    Text(formatXof(l.totalXof), style: t.bodyMedium),
                  ],
                ),
              ),
            divider,
            amount('Sous-total', invoice.subtotalXof),
            if (invoice.deliveryXof > 0)
              amount('Livraison', invoice.deliveryXof),
            const SizedBox(height: IviaSpacing.sm),
            amount('Montant total', invoice.totalXof, strong: true),
            divider,
            Text(
              invoice.paymentNote,
              style: t.bodyMedium?.copyWith(
                color: invoice.isReceipt
                    ? IviaColors.success
                    : IviaColors.secondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bords haut et bas découpés en demi-cercles, comme un ticket détaché.
class _SawEdges extends CustomClipper<Path> {
  const _SawEdges();

  static const _r = 7.0;

  @override
  Path getClip(Size size) {
    final n = (size.width / (_r * 3)).floor().clamp(4, 200);
    final step = size.width / n;
    final p = Path()..moveTo(0, 0);
    for (var i = 0; i < n; i++) {
      final cx = step * i + step / 2;
      p
        ..lineTo(cx - _r, 0)
        ..arcToPoint(
          Offset(cx + _r, 0),
          radius: const Radius.circular(_r),
          clockwise: false,
        );
    }
    p
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height);
    for (var i = n - 1; i >= 0; i--) {
      final cx = step * i + step / 2;
      p
        ..lineTo(cx + _r, size.height)
        ..arcToPoint(
          Offset(cx - _r, size.height),
          radius: const Radius.circular(_r),
          clockwise: false,
        );
    }
    return p
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(_SawEdges oldClipper) => false;
}
