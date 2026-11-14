import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

/// Origine d'une photo.
enum PhotoSource { camera, gallery }

/// Choix d'une photo prête à l'envoi : JPEG dont le plus grand côté fait au
/// plus [maxSide] px, sans métadonnées (position GPS comprise),
/// docs/SECURITY.md.
abstract interface class PhotoPicker {
  /// `null` : choix annulé.
  Future<Uint8List?> pick({
    PhotoSource source = PhotoSource.gallery,
    int maxSide = 1024,
  });
}

class DevicePhotoPicker implements PhotoPicker {
  const DevicePhotoPicker();

  @override
  Future<Uint8List?> pick({
    PhotoSource source = PhotoSource.gallery,
    int maxSide = 1024,
  }) async {
    // image_picker borne le plus grand côté en gardant les proportions.
    final file = await ImagePicker().pickImage(
      source: source == PhotoSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      maxWidth: maxSide.toDouble(),
      maxHeight: maxSide.toDouble(),
      requestFullMetadata: false,
    );
    if (file == null) return null;
    // Réencodage en JPEG sans métadonnées. minWidth / minHeight ne font que
    // réduire une image plus grande : la taille déjà bornée est conservée.
    return FlutterImageCompress.compressWithList(
      await file.readAsBytes(),
      minWidth: maxSide,
      minHeight: maxSide,
      quality: 85,
      format: CompressFormat.jpeg,
      keepExif: false,
    );
  }
}

final photoPickerProvider = Provider<PhotoPicker>(
  (ref) => const DevicePhotoPicker(),
);
