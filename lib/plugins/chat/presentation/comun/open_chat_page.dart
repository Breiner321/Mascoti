import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/auth_providers.dart';
import '../../../../core/auth/domain/app_user.dart';
import '../../../../core/data/chat_providers.dart';
import '../../../../core/data/chat_repository.dart';
import '../../chat_routes.dart';
import 'chat_ui_providers.dart';

/// Abre o crea la conversación y la reemplaza por `/chat/:chatId` (RF-15
/// paso 2). La usan "Enviar mensaje" del perfil del paciente y del detalle
/// de una cita (clínica: [ownerUid], [ownerNombre] y [petId]) y, si hace
/// falta, el dueño ([clinicId]).
class OpenChatPage extends ConsumerStatefulWidget {
  const OpenChatPage({
    super.key,
    this.ownerUid,
    this.ownerNombre,
    this.petId,
    this.clinicId,
  });

  final String? ownerUid;
  final String? ownerNombre;
  final String? petId;
  final String? clinicId;

  @override
  ConsumerState<OpenChatPage> createState() => _OpenChatPageState();
}

class _OpenChatPageState extends ConsumerState<OpenChatPage> {
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    setState(() => _error = null);
    final user = ref.read(currentUserProvider);
    final chats = ref.read(chatRepositoryProvider);
    final lookup = ref.read(chatLookupRepositoryProvider);
    try {
      if (user == null) throw const ChatFailure('Inicia sesión para enviar mensajes.');
      final String id;
      if (user.role == UserRole.clinica) {
        final clinicId = user.clinicId;
        final ownerUid = widget.ownerUid;
        final petId = widget.petId;
        if (clinicId == null || ownerUid == null || ownerUid.isEmpty || petId == null) {
          throw const ChatFailure('No se pudo abrir la conversación.');
        }
        final clinic = await lookup.fetchClinic(clinicId);
        if (clinic == null) throw const ChatFailure('No se pudo abrir la conversación.');
        final ownerNombre = (widget.ownerNombre ?? '').trim();
        final chat = await chats.openChat(
          ownerUid: ownerUid,
          ownerNombre: ownerNombre.isEmpty ? 'Dueño' : ownerNombre,
          clinicId: clinicId,
          clinicOwnerUid: user.uid,
          clinicNombre: clinic.nombre,
          petIds: [petId],
        );
        id = chat.id;
      } else {
        final clinicId = widget.clinicId;
        if (clinicId == null) throw const ChatFailure('No se pudo abrir la conversación.');
        final clinic = await lookup.fetchClinic(clinicId);
        if (clinic == null) throw const ChatFailure('Esta clínica ya no está disponible.');
        final chat = await chats.openChat(
          ownerUid: user.uid,
          ownerNombre: user.nombreVisible,
          clinicId: clinicId,
          clinicOwnerUid: clinic.ownerUid,
          clinicNombre: clinic.nombre,
          petIds: [if (widget.petId case final petId?) petId],
        );
        id = chat.id;
      }
      if (mounted) context.replace(ChatRoutes.conversation(id));
    } on ChatFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudo abrir la conversación. Intenta de nuevo.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return Scaffold(
      appBar: AppBar(title: const Text('Mensajes')),
      body: Center(
        child: error == null
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(error, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _open, child: const Text('Reintentar')),
                  ],
                ),
              ),
      ),
    );
  }
}
