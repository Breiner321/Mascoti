import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/domain/chat_message.dart';
import '../../../../core/format/relative_time.dart';
import '../../../../core/theme/app_theme.dart';
import '../comun/chat_ui_providers.dart';
import 'clinic_inbox_filter.dart';

/// Fila de la bandeja de la clínica: dueño (iniciales y, si tiene una sola
/// mascota con foto, la foto), mascotas vinculadas, vista previa del último
/// mensaje, hora y no leídos.
class ClinicChatTile extends ConsumerWidget {
  const ClinicChatTile({
    super.key,
    required this.entry,
    required this.clinicUid,
    required this.now,
    required this.onTap,
  });

  final ClinicInboxEntry entry;
  final String clinicUid;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final chat = entry.chat;
    final unread = chat.unreadFor(clinicUid);
    final last = chat.lastMessage;
    final owner = chat.ownerNombre.isEmpty ? 'Dueño' : chat.ownerNombre;
    final petNames = entry.pets.map((p) => p.nombre).join(', ');
    final preview = switch (last) {
      null => 'Sin mensajes',
      _ => [
          if (last.senderUid == clinicUid) 'Tú:',
          if (last.tipo == ChatMessageType.adjunto) '📎',
          last.texto,
        ].join(' '),
    };
    final at = chat.lastMessageAt;
    final bold = unread > 0 ? const TextStyle(fontWeight: FontWeight.bold) : null;

    return ListTile(
      onTap: onTap,
      leading: _OwnerAvatar(
        name: owner,
        petPhotoPath: entry.pets.length == 1 ? entry.pets.single.fotoPath : null,
      ),
      title: Text(owner, maxLines: 1, overflow: TextOverflow.ellipsis, style: bold),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (petNames.isNotEmpty)
            Row(
              children: [
                Icon(Icons.pets, size: 14, color: AppColors.primary),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    petNames,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: AppColors.primary),
                  ),
                ),
              ],
            ),
          Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis, style: bold),
        ],
      ),
      isThreeLine: petNames.isNotEmpty,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (at != null)
            Text(
              relativeTime(at, now),
              style: theme.textTheme.bodySmall?.copyWith(
                color: unread > 0 ? AppColors.primary : AppColors.textMuted,
              ),
            ),
          if (unread > 0) ...[
            const SizedBox(height: 4),
            Semantics(
              label: '$unread sin leer',
              excludeSemantics: true,
              child: Badge(label: Text('$unread')),
            ),
          ],
        ],
      ),
    );
  }
}

class _OwnerAvatar extends ConsumerWidget {
  const _OwnerAvatar({required this.name, this.petPhotoPath});

  final String name;
  final String? petPhotoPath;

  String get _initials {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    final first = words.first.characters.first;
    final second = words.length > 1 ? words[1].characters.first : '';
    return '$first$second'.toUpperCase();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = petPhotoPath;
    final photo = path == null ? null : ref.watch(chatPetPhotoUrlProvider(path)).value;
    return Semantics(
      label: 'Foto de $name',
      excludeSemantics: true,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Stack(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.primaryContainer,
              foregroundColor: AppColors.primary,
              child: Text(_initials, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            if (photo != null)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.surface, width: 2),
                    image: DecorationImage(image: NetworkImage(photo), fit: BoxFit.cover),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
