import 'package:flutter/foundation.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Ligne de facture.
class InvoiceLine {
  const InvoiceLine(this.label, this.quantity, this.unitXof, this.totalXof);
  final String label;
  final int quantity, unitXof, totalXof;
}

/// Facture à télécharger (commande payée, réservation pharmacie réglée).
class Invoice {
  const Invoice({
    required this.number,
    required this.date,
    required this.seller,
    required this.sellerAddress,
    required this.customer,
    required this.customerPhone,
    required this.lines,
    required this.subtotalXof,
    required this.deliveryXof,
    required this.totalXof,
    required this.paymentNote,
    this.closedLabel,
  });

  /// Commande annulée, expirée ou remboursée : un récapitulatif, pas un reçu
  /// de paiement.
  bool get isReceipt => closedLabel == null;

  /// « Commande annulée », « Commande expirée »… ; `null` pour un reçu.
  final String? closedLabel;

  String get title =>
      isReceipt ? 'Reçu de paiement' : 'Récapitulatif de commande';

  /// Facture d'une commande de boutique.
  factory Invoice.fromOrder(BuyerOrder o, User? me) => Invoice(
    number: 'IVIA-C${o.number.toString().padLeft(6, '0')}',
    date: o.paidAt ?? o.createdAt,
    seller: o.shop.name,
    sellerAddress: [
      o.shop.addressText,
      o.shop.neighborhoodName,
    ].where((s) => s.isNotEmpty).join(', '),
    customer: [
      me?.firstName,
      me?.lastName,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' '),
    customerPhone: me?.phone ?? '',
    lines: [
      for (final i in o.items)
        InvoiceLine(i.name, i.quantity, i.unitPriceXof, i.lineTotalXof),
    ],
    subtotalXof: o.subtotalXof,
    deliveryXof: o.deliveryFeeXof,
    totalXof: o.totalXof,
    closedLabel: switch (o.status) {
      OrderStatus.cancelled => 'Commande annulée',
      OrderStatus.expired => 'Commande expirée',
      OrderStatus.refunded => 'Commande remboursée',
      OrderStatus.returnedToShop => 'Commande retournée',
      _ => null,
    },
    paymentNote: switch ((o.status, o.paidAt)) {
      (OrderStatus.cancelled || OrderStatus.expired, null) =>
        'Aucun paiement n’a été débité.',
      (OrderStatus.refunded, final DateTime p) =>
        'Payée le ${_date(p)}, puis remboursée.',
      (OrderStatus.cancelled || OrderStatus.returnedToShop, final DateTime p) =>
        'Payée le ${_date(p)} · remboursement en cours.',
      (_, null) => 'En attente de paiement',
      (_, final DateTime p) => 'Payée par Mobile Money le ${_date(p)}',
    },
  );

  /// Facture d'une réservation pharmacie (produits payés dans l'app ou sur place).
  factory Invoice.fromReservation(MedReservation r, User? me) => Invoice(
    number: 'IVIA-${r.number}',
    date: r.paidAt ?? r.deliveredAt ?? DateTime.now(),
    seller: r.pharmacy.name,
    sellerAddress: r.pharmacy.addressText,
    customer: [
      me?.firstName,
      me?.lastName,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' '),
    customerPhone: me?.phone ?? '',
    lines: [
      for (final l in r.lines.where((l) => l.available))
        InvoiceLine(l.name, l.quantity, l.unitPriceXof, l.lineTotalXof),
    ],
    subtotalXof: r.itemsXof,
    deliveryXof: r.deliveryFeeXof,
    totalXof: r.delivery ? r.totalXof : r.itemsXof,
    paymentNote: r.payInApp && r.paidAt != null
        ? 'Payée par Mobile Money le ${_date(r.paidAt!)}'
        : 'Produits payés à la pharmacie',
  );

  final String number,
      seller,
      sellerAddress,
      customer,
      customerPhone,
      paymentNote;
  final DateTime date;
  final List<InvoiceLine> lines;
  final int subtotalXof, deliveryXof, totalXof;

  static String _date(DateTime d) {
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}/${two(l.month)}/${l.year} à ${two(l.hour)}:${two(l.minute)}';
  }

  /// PDF aux couleurs d'ivia.
  Future<Uint8List> pdf() async {
    final doc = pw.Document(
      title: '${isReceipt ? 'Facture' : 'Récapitulatif'} $number',
      author: 'ivia',
    );
    const navy = PdfColor.fromInt(0xFF0E2E54);
    const red = PdfColor.fromInt(0xFFE31B2C);
    const muted = PdfColor.fromInt(0xFF6B7280);
    final font = await PdfGoogleFonts.poppinsRegular();
    final bold = await PdfGoogleFonts.poppinsBold();
    String f(int x) => '${groupDigits(x)} FCFA';
    pw.Widget cell(
      String s, {
      bool b = false,
      pw.TextAlign a = pw.TextAlign.left,
      PdfColor? c,
    }) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: pw.Text(
        s,
        textAlign: a,
        style: pw.TextStyle(font: b ? bold : font, fontSize: 10, color: c),
      ),
    );
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              padding: const pw.EdgeInsets.all(18),
              decoration: const pw.BoxDecoration(
                color: navy,
                borderRadius: pw.BorderRadius.all(pw.Radius.circular(12)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'ivia',
                    style: pw.TextStyle(
                      font: bold,
                      fontSize: 28,
                      color: PdfColors.white,
                    ),
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        isReceipt ? 'FACTURE' : 'RÉCAPITULATIF',
                        style: pw.TextStyle(
                          font: bold,
                          fontSize: 14,
                          color: PdfColors.white,
                        ),
                      ),
                      pw.Text(
                        number,
                        style: pw.TextStyle(
                          font: font,
                          fontSize: 11,
                          color: PdfColors.white,
                        ),
                      ),
                      pw.Text(
                        _date(date),
                        style: pw.TextStyle(
                          font: font,
                          fontSize: 9,
                          color: PdfColors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 22),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'VENDEUR',
                        style: pw.TextStyle(
                          font: bold,
                          fontSize: 9,
                          color: muted,
                        ),
                      ),
                      pw.Text(
                        seller,
                        style: pw.TextStyle(font: bold, fontSize: 12),
                      ),
                      pw.Text(
                        sellerAddress,
                        style: pw.TextStyle(font: font, fontSize: 10),
                      ),
                      pw.Text(
                        'Vendu via ivia, Lomé (Togo)',
                        style: pw.TextStyle(
                          font: font,
                          fontSize: 9,
                          color: muted,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'CLIENT',
                        style: pw.TextStyle(
                          font: bold,
                          fontSize: 9,
                          color: muted,
                        ),
                      ),
                      pw.Text(
                        customer.isEmpty ? 'Client ivia' : customer,
                        style: pw.TextStyle(font: bold, fontSize: 12),
                      ),
                      if (customerPhone.isNotEmpty)
                        pw.Text(
                          customerPhone,
                          style: pw.TextStyle(font: font, fontSize: 10),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 22),
            pw.Table(
              columnWidths: const {
                0: pw.FlexColumnWidth(5),
                1: pw.FlexColumnWidth(1),
                2: pw.FlexColumnWidth(2),
                3: pw.FlexColumnWidth(2),
              },
              border: const pw.TableBorder(
                horizontalInside: pw.BorderSide(
                  color: PdfColors.grey300,
                  width: .5,
                ),
              ),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    cell('Désignation', b: true),
                    cell('Qté', b: true, a: pw.TextAlign.right),
                    cell('Prix unitaire', b: true, a: pw.TextAlign.right),
                    cell('Total', b: true, a: pw.TextAlign.right),
                  ],
                ),
                for (final l in lines)
                  pw.TableRow(
                    children: [
                      cell(l.label),
                      cell('${l.quantity}', a: pw.TextAlign.right),
                      cell(f(l.unitXof), a: pw.TextAlign.right),
                      cell(f(l.totalXof), a: pw.TextAlign.right),
                    ],
                  ),
              ],
            ),
            pw.SizedBox(height: 16),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.SizedBox(
                width: 230,
                child: pw.Column(
                  children: [
                    for (final (label, value) in [
                      ('Sous-total', subtotalXof),
                      if (deliveryXof > 0) ('Livraison', deliveryXof),
                    ])
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          cell(label),
                          cell(f(value), a: pw.TextAlign.right),
                        ],
                      ),
                    pw.Divider(color: PdfColors.grey400),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        cell('Total TTC', b: true),
                        cell(
                          f(totalXof),
                          b: true,
                          c: red,
                          a: pw.TextAlign.right,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            pw.SizedBox(height: 18),
            pw.Text(
              paymentNote,
              style: pw.TextStyle(font: bold, fontSize: 10, color: navy),
            ),
            pw.Spacer(),
            pw.Divider(color: PdfColors.grey300),
            pw.Text(
              isReceipt
                  ? 'Merci pour votre achat. Cette facture est émise pour le compte du vendeur via la plateforme ivia.'
                  : '${closedLabel!}. Ce récapitulatif n’est pas une facture.',
              style: pw.TextStyle(font: font, fontSize: 8, color: muted),
            ),
          ],
        ),
      ),
    );
    return doc.save();
  }

  /// Télécharge (web) ou partage (téléphone) le PDF.
  Future<void> download() async =>
      Printing.sharePdf(bytes: await pdf(), filename: 'facture-$number.pdf');
}
