import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/auth_providers.dart';
import '../../../../core/data/chat_providers.dart';
import '../../../../core/domain/pet.dart';
import '../../../../core/theme/app_theme.dart';
import '../../chat_routes.dart';
import '../comun/chat_ui_providers.dart';
import 'clinic_chat_tile.dart';
import 'clinic_inbox_filter.dart';

/// Reloj de la bandeja (hora de cada conversación). Se reemplaza en pruebas.
final inboxClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Bandeja de mensajes de la clínica (pestaña "Mensajes", RF-15): las
/// conversaciones con sus clientes, la más reciente primero, con buscador
/// por dueño o mascota y el filtro "Sin leer".
class ClinicInboxPage extends ConsumerStatefulWidget {
  const ClinicInboxPage({super.key});

  @override
  ConsumerState<ClinicInboxPage> createState() => _ClinicInboxPageState();
}

class _ClinicInboxPageState extends ConsumerState<ClinicInboxPage> {
  final _search = TextEditingController();
  String _query = '';
  bool _unreadOnly = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const Center(child: CircularProgressIndicator());
    final chats = ref.watch(userChatsProvider(user.uid));
    final clinicId = user.clinicId;
    // Si las mascotas no cargan, la bandeja se muestra igual (sin mascotas).
    final pets = clinicId == null
        ? const <Pet>[]
        : ref.watch(linkedPetsProvider(clinicId)).value ?? const <Pet>[];

    return switch (chats) {
      AsyncData(:final value) when value.isEmpty => const _Centered(
          icon: Icons.chat_bubble_outline,
          text: 'Aún no tienes conversaciones con tus clientes.',
          detail: 'Escríbele a un dueño con "Enviar mensaje" desde el perfil del paciente '
              'o el detalle de una cita.',
        ),
      AsyncData(:final value) => _list(
          buildClinicInbox(
            chats: value,
            linkedPets: pets,
            clinicUid: user.uid,
            query: _query,
            unreadOnly: _unreadOnly,
          ),
          user.uid,
        ),
      AsyncError() => _Centered(
          icon: Icons.cloud_off,
          text: 'No se pudieron cargar tus mensajes.',
          action: FilledButton(
            onPressed: () => ref.invalidate(userChatsProvider(user.uid)),
            child: const Text('Reintentar'),
          ),
        ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }

  Widget _list(List<ClinicInboxEntry> entries, String uid) {
    final now = ref.watch(inboxClockProvider)();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: _search,
            onChanged: (v) => setState(() => _query = v),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Buscar por dueño o mascota',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Borrar búsqueda',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() {
                        _search.clear();
                        _query = '';
                      }),
                    ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilterChip(
              label: const Text('Sin leer'),
              selected: _unreadOnly,
              onSelected: (v) => setState(() => _unreadOnly = v),
            ),
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? _Centered(
                  icon: _unreadOnly && _query.trim().isEmpty
                      ? Icons.mark_chat_read_outlined
                      : Icons.search_off,
                  text: _unreadOnly && _query.trim().isEmpty
                      ? 'No tienes mensajes sin leer.'
                      : 'No hay conversaciones que coincidan con la búsqueda.',
                )
              : ListView.separated(
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) => ClinicChatTile(
                    key: ValueKey(entries[i].chat.id),
                    entry: entries[i],
                    clinicUid: uid,
                    now: now,
                    onTap: () => context.push(ChatRoutes.conversation(entries[i].chat.id)),
                  ),
                ),
        ),
      ],
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.icon, required this.text, this.detail, this.action});

  final IconData icon;
  final String text;
  final String? detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
            if (detail != null) ...[
              const SizedBox(height: 4),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 12), action!],
          ],
        ),
      ),
    );
  }
}
