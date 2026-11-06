import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';

import '../../common/ui.dart';
import '../push/push.dart';
import 'application_screen.dart';
import 'step_details.dart';

/// Nombre d'étapes du dossier : fiche, carte, pièces, planning, versement.
const dossierSteps = 5;

/// Étape où reprendre un dossier : la première incomplète. Des compléments
/// demandés ou un refus rouvrent la fiche, où s'affiche le motif.
int initialDossierStep(PharmacyProfile? p) {
  if (p == null) return 1;
  if (p.reviewStatus != 'draft' && p.reviewNote.isNotEmpty) return 1;
  if (p.missingDocuments.isNotEmpty) return 3;
  if (!p.hasPayout) return 4;
  return 5;
}

/// Dossier en 5 étapes (F06 à F07), avec la pastille « n sur 5 ». Le retour
/// ramène à l'étape précédente ; depuis la fiche, il déconnecte.
class ApplicationFlow extends ConsumerStatefulWidget {
  const ApplicationFlow({super.key, required this.profile});
  final PharmacyProfile? profile;

  @override
  ConsumerState<ApplicationFlow> createState() => _ApplicationFlowState();
}

class _ApplicationFlowState extends ConsumerState<ApplicationFlow> {
  late var _step = initialDossierStep(widget.profile);

  /// Devanture choisie à l'étape 1, envoyée une fois la pharmacie créée.
  Uint8List? _storefront;

  void _back() {
    switch (_step) {
      case 1:
        signOutPharmacy(ref);
      case 3:
        setState(() => _step = 1);
      default:
        setState(() => _step -= 1);
    }
  }

  PHeader _header(String title) => PHeader(
    title: title,
    trailing: PStepPill(step: _step, of: dossierSteps),
    onBack: _back,
  );

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final Widget body;
    if (_step == 1) {
      body = DetailsStep(
        profile: profile,
        storefront: _storefront,
        onStorefront: (bytes) => setState(() => _storefront = bytes),
        onSaved: () => setState(() => _step = 3),
        header: _header('Votre pharmacie'),
      );
    } else if (profile == null) {
      // Pharmacie tout juste créée : relecture en cours.
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = DossierHub(
        profile: profile,
        onEditDetails: () => setState(() => _step = 1),
      );
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: P.page,
        body: SafeArea(child: body),
      ),
    );
  }
}
