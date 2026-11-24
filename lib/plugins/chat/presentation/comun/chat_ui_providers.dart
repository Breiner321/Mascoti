import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/attachments/attachment_picker.dart';
import '../../../../core/data/chat_providers.dart';
import '../../../../core/domain/pet.dart';
import '../../../../core/storage/storage_providers.dart';
import '../../../../core/storage/storage_repository.dart';
import '../../data/chat_lookup_repository.dart';
import '../../data/file_downloader.dart';
import 'adjuntos/attachment_link_cache.dart';
import 'adjuntos/attachment_prep.dart';

final chatLookupRepositoryProvider = Provider<ChatLookupRepository>(
  (ref) => ChatLookupRepository(),
);

/// Mascotas que autorizaron a la clínica `clinicId`, en tiempo real.
final linkedPetsProvider = StreamProvider.autoDispose.family<List<Pet>, String>(
  (ref, clinicId) => ref.watch(chatLookupRepositoryProvider).watchLinkedPets(clinicId),
  retry: (_, __) => null,
);

/// Una mascota (para `"Del historial médico de <mascota>"`); null si no se
/// puede leer.
final chatPetProvider = FutureProvider.autoDispose.family<Pet?, String>(
  (ref, petId) => ref.watch(chatLookupRepositoryProvider).fetchPet(petId),
  retry: (_, __) => null,
);

/// Enlace temporal de la foto de una mascota (bucket `mascotas`).
final chatPetPhotoUrlProvider = FutureProvider.autoDispose.family<String, String>(
  (ref, path) => ref
      .watch(storageRepositoryProvider)
      .signedUrl(path, bucketId: StorageRepository.petsBucket),
  retry: (_, __) => null,
);

final chatAttachmentPickerProvider = Provider<AttachmentPicker>(
  (ref) => const AttachmentPicker(),
);

final imageCompressorProvider = Provider<ImageCompressor>((ref) => compressWithPlugin);

final fileDownloaderProvider = Provider<FileDownloader>((ref) => downloadWithHttp);

/// Enlaces de lectura de los adjuntos del chat, renovados sin que el
/// usuario lo note cuando vencen.
final attachmentLinkCacheProvider = Provider<AttachmentLinkCache>(
  (ref) => AttachmentLinkCache(ref.watch(chatRepositoryProvider).attachmentUrl),
);

/// Abre un PDF fuera de la app (visor o navegador del teléfono, que permiten
/// verlo y descargarlo), igual que el historial médico.
final chatUrlOpenerProvider = Provider<Future<bool> Function(Uri)>(
  (ref) => (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);
