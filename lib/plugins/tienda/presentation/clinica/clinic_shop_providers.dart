import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/auth_providers.dart';
import '../../../../core/data/shop_providers.dart';
import '../../../../core/domain/order.dart';
import '../../../../core/images/photo_compression.dart';
import '../../../../core/storage/storage_providers.dart';
import '../../../../core/storage/storage_repository.dart';

/// Cámara o galería para la foto del producto (se reemplaza en las pruebas).
final productPhotoPickerProvider = Provider<PhotoPicker>((ref) => DevicePhotoPicker());

/// Enlace temporal para mostrar la foto de un producto (bucket `productos`).
final productPhotoUrlProvider = FutureProvider.autoDispose.family<String, String>(
  (ref, path) => ref
      .watch(storageRepositoryProvider)
      .signedUrl(path, bucketId: StorageRepository.productsBucket),
  retry: (_, __) => null,
);

/// Pedidos pagados que la clínica aún no empieza a preparar: número de la
/// pestaña "Inventario" y del acceso a "Pedidos" (0 sin conexión o error).
final pendingClinicOrdersCountProvider = Provider.autoDispose<int>((ref) {
  final clinicId = ref.watch(currentUserProvider)?.clinicId;
  if (clinicId == null) return 0;
  final orders = ref.watch(clinicOrdersProvider(clinicId)).value ?? const [];
  return orders.where((o) => o.estado == OrderStatus.pagado).length;
});
