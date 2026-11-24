import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/qr_tag.dart';
import 'qr_tags_repository.dart';

final qrTagsRepositoryProvider = Provider<QrTagsRepository>((ref) => QrTagsRepository());

/// Placa vigente de una mascota del dueño: `petQrTagProvider((ownerUid: u, petId: p))`.
final petQrTagProvider = StreamProvider.autoDispose
    .family<QrTag?, ({String ownerUid, String petId})>(
  (ref, q) => ref.watch(qrTagsRepositoryProvider).watchPetTag(q.ownerUid, q.petId),
  retry: (_, __) => null,
);
