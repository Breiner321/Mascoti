import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/appointment.dart';
import '../format/bogota_time.dart';

/// Error de una acción sobre una cita, con el mensaje para mostrar.
@immutable
class AppointmentFailure implements Exception {
  const AppointmentFailure(this.message, {this.canRetry = false, this.slotTaken = false});

  final String message;
  final bool canRetry;

  /// Otro usuario tomó el horario: la pantalla debe refrescar el calendario
  /// (RF-14, flujo alterno).
  final bool slotTaken;

  static const network = AppointmentFailure(
    'No se pudo conectar. Verifica tu conexión',
    canRetry: true,
  );
  static const notConfigured =
      AppointmentFailure('Las citas no están disponibles en esta versión de la app');
  static const slotUnavailable = AppointmentFailure(
    'Este horario ya no está disponible, por favor selecciona otro',
    slotTaken: true,
  );

  @override
  String toString() => 'AppointmentFailure($message)';
}

/// Citas (RF-14), compartido por las pantallas del dueño y de la clínica.
///
/// - Lectura: `appointments` en Firestore, en tiempo real.
/// - Escritura: SOLO con la Edge Function `citas` de Supabase, que valida y
///   hace las transacciones (las reglas no dejan escribir desde la app).
///
/// Los métodos de escritura lanzan [AppointmentFailure] con el mensaje en
/// español que devuelve el servidor.
class AppointmentsRepository {
  AppointmentsRepository({FirebaseFirestore? firestore, FunctionsClient? functions})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _functions = functions;

  final FirebaseFirestore _firestore;

  /// null = Supabase no está configurado (falta env/dev.json).
  final FunctionsClient? _functions;

  static const functionName = 'citas';
  static const _timeout = Duration(seconds: 30);

  CollectionReference<Map<String, dynamic>> get _appointments =>
      _firestore.collection('appointments');

  static List<Appointment> _list(QuerySnapshot<Map<String, dynamic>> snap) =>
      [for (final d in snap.docs) Appointment.fromMap(d.id, d.data())];

  // ---------------------------------------------------------------------------
  // Lectura
  // ---------------------------------------------------------------------------

  /// "Mis citas" del dueño: todas, de la más lejana en el futuro a la más
  /// antigua (inicio descendente).
  Stream<List<Appointment>> watchOwnerAppointments(String ownerUid) => _appointments
      .where('ownerUid', isEqualTo: ownerUid)
      .orderBy('inicio', descending: true)
      .snapshots()
      .map(_list);

  /// Bandeja "Solicitudes pendientes" de la clínica, la más próxima primero.
  Stream<List<Appointment>> watchPendingRequests(String clinicId) => _appointments
      .where('clinicId', isEqualTo: clinicId)
      .where('estado', isEqualTo: AppointmentStatus.pendiente.value)
      .orderBy('inicio')
      .snapshots()
      .map(_list);

  /// Agenda de la clínica: citas con inicio en [from, to), en cualquier
  /// estado (la pantalla decide cuáles mostrar), por hora.
  Stream<List<Appointment>> watchAgenda(
    String clinicId, {
    required DateTime from,
    required DateTime to,
  }) =>
      _appointments
          .where('clinicId', isEqualTo: clinicId)
          .where('inicio', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
          .where('inicio', isLessThan: Timestamp.fromDate(to))
          .orderBy('inicio')
          .snapshots()
          .map(_list);

  /// Agenda de un día del calendario ([day] como lo da un selector de
  /// fechas), de 00:00 a 24:00 en hora de Bogotá.
  Stream<List<Appointment>> watchDay(String clinicId, DateTime day) {
    final from = BogotaTime.startOfCalendarDay(day);
    return watchAgenda(clinicId, from: from, to: from.add(const Duration(days: 1)));
  }

  /// Una cita (detalle `/reservas/:id`), o null si no existe.
  Stream<Appointment?> watchAppointment(String appointmentId) =>
      _appointments.doc(appointmentId).snapshots().map(
            (d) => d.exists ? Appointment.fromMap(d.id, d.data()!) : null,
          );

  // ---------------------------------------------------------------------------
  // Acciones (Edge Function `citas`)
  // ---------------------------------------------------------------------------

  /// El dueño solicita una cita (RF-14 paso 5). Devuelve el id de la cita.
  /// Si el horario ya no está libre lanza [AppointmentFailure.slotUnavailable]
  /// (`slotTaken == true`).
  Future<String> request({
    required String clinicId,
    required String serviceId,
    required String petId,
    required String slotId,
    String comentario = '',
  }) async {
    if (comentario.trim().length > AppointmentLimits.maxComentario) {
      throw const AppointmentFailure(
        'El comentario no puede superar ${AppointmentLimits.maxComentario} caracteres.',
      );
    }
    final data = await _invoke({
      'accion': 'solicitar',
      'clinicId': clinicId,
      'serviceId': serviceId,
      'petId': petId,
      'slotId': slotId,
      'comentario': comentario.trim(),
    });
    return data['appointmentId'] as String;
  }

  /// La clínica aprueba la solicitud (→ confirmada).
  Future<void> approve(String appointmentId) =>
      _invoke({'accion': 'responder', 'appointmentId': appointmentId, 'aprobar': true});

  /// La clínica rechaza la solicitud; [motivo] es obligatorio.
  Future<void> reject(String appointmentId, String motivo) async {
    _checkReason(motivo, required: true, emptyMessage: 'Indica el motivo del rechazo.');
    await _invoke({
      'accion': 'responder',
      'appointmentId': appointmentId,
      'aprobar': false,
      'motivo': motivo.trim(),
    });
  }

  /// Cancela la cita. El dueño puede hasta 2 h antes y sin motivo; la
  /// clínica ([byClinic]) siempre con motivo.
  Future<void> cancel(String appointmentId, {String? motivo, bool byClinic = false}) async {
    _checkReason(
      motivo,
      required: byClinic,
      emptyMessage: 'Indica el motivo de la cancelación.',
    );
    final reason = motivo?.trim() ?? '';
    await _invoke({
      'accion': 'cancelar',
      'appointmentId': appointmentId,
      if (reason.isNotEmpty) 'motivo': reason,
    });
  }

  /// La clínica marca la cita como atendida (solo después de su inicio).
  Future<void> complete(String appointmentId) =>
      _invoke({'accion': 'completar', 'appointmentId': appointmentId});

  static void _checkReason(
    String? motivo, {
    required bool required,
    required String emptyMessage,
  }) {
    final reason = motivo?.trim() ?? '';
    if (required && reason.isEmpty) throw AppointmentFailure(emptyMessage);
    if (reason.length > AppointmentLimits.maxMotivo) {
      throw const AppointmentFailure(
        'El motivo no puede superar ${AppointmentLimits.maxMotivo} caracteres.',
      );
    }
  }

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    final functions = _functions;
    if (functions == null) throw AppointmentFailure.notConfigured;
    try {
      final response = await functions.invoke(functionName, body: body).timeout(_timeout);
      return Map<String, dynamic>.from(response.data as Map);
    } on TimeoutException {
      throw AppointmentFailure.network;
    } on SocketException {
      throw AppointmentFailure.network;
    } on http.ClientException {
      throw AppointmentFailure.network;
    } on FunctionException catch (e) {
      final error = e.details is Map ? (e.details as Map)['error'] : null;
      final code = error is Map ? error['code'] as String? : null;
      final message = error is Map ? error['message'] as String? : null;
      if (code == 'aborted' && message == AppointmentFailure.slotUnavailable.message) {
        throw AppointmentFailure.slotUnavailable;
      }
      throw AppointmentFailure(
        message ?? 'No se pudo completar la acción. Intenta de nuevo.',
        canRetry: e.status >= 500 || code == 'aborted',
      );
    }
  }
}
