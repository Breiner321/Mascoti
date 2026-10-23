import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/domain/appointment.dart';
import 'package:mascoti/core/format/bogota_time.dart';

void main() {
  /// Las únicas transiciones válidas (RF-14). Igual que en
  /// functions/test/estados_cita.test.ts.
  const valid = {
    (AppointmentStatus.pendiente, AppointmentStatus.confirmada),
    (AppointmentStatus.pendiente, AppointmentStatus.rechazada),
    (AppointmentStatus.pendiente, AppointmentStatus.cancelada),
    (AppointmentStatus.pendiente, AppointmentStatus.expirada),
    (AppointmentStatus.confirmada, AppointmentStatus.completada),
    (AppointmentStatus.confirmada, AppointmentStatus.cancelada),
    (AppointmentStatus.confirmada, AppointmentStatus.noAsistio),
  };

  group('máquina de estados', () {
    test('7 estados con los valores de Firestore (iguales al servidor)', () {
      expect(AppointmentStatus.values.map((s) => s.value), [
        'pendiente', 'confirmada', 'rechazada', 'cancelada', 'expirada', 'completada', 'no_asistio',
      ]);
      expect(AppointmentStatus.fromValue('no_asistio'), AppointmentStatus.noAsistio);
      expect(AppointmentStatus.fromValue('aprobada'), isNull);
    });

    test('recorre las 49 combinaciones: solo las válidas se permiten', () {
      for (final from in AppointmentStatus.values) {
        for (final to in AppointmentStatus.values) {
          expect(canTransition(from, to), valid.contains((from, to)), reason: '$from → $to');
        }
      }
    });

    test('estados finales y activos', () {
      expect(AppointmentStatus.values.where((s) => s.isFinal), [
        AppointmentStatus.rechazada,
        AppointmentStatus.cancelada,
        AppointmentStatus.expirada,
        AppointmentStatus.completada,
        AppointmentStatus.noAsistio,
      ]);
      expect(AppointmentStatus.pendiente.isActive, isTrue);
      expect(AppointmentStatus.confirmada.isActive, isTrue);
      expect(AppointmentStatus.pendiente.nextStates, hasLength(4));
    });
  });

  group('Appointment', () {
    final inicio = BogotaTime.at(2026, 11, 5, 9, 30);
    final doc = <String, dynamic>{
      'clinicId': 'c1',
      'clinicNombre': 'Vet Norte',
      'clinicOwnerUid': 'vet',
      'ownerUid': 'ana',
      'ownerNombre': 'Ana Pérez',
      'petId': 'p1',
      'petNombre': 'Luna',
      'serviceId': 's1',
      'serviceNombre': 'Consulta general',
      'precioAcordado': 45000,
      'duracionMin': 30,
      'slotId': '2026-11-05_09:30',
      'fecha': '2026-11-05',
      'hora': '09:30',
      'inicio': Timestamp.fromDate(inicio),
      'comentario': 'Vómito desde ayer',
      'estado': 'confirmada',
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 11, 1)),
    };

    test('fromMap lee todos los campos; toMap → fromMap los conserva', () {
      final a = Appointment.fromMap('a1', doc);
      expect(a.estado, AppointmentStatus.confirmada);
      expect(a.inicio, inicio);
      expect(a.precioAcordado, 45000);
      expect(a.duracionMin, 30);
      expect(a.ownerNombre, 'Ana Pérez');
      expect(Appointment.fromMap('a1', a.toMap()), a);
    });

    test('cancelación de la clínica con motivo', () {
      final a = Appointment.fromMap('a1', {
        ...doc,
        'estado': 'cancelada',
        'canceladoPor': 'clinica',
        'motivoCancelacion': 'Imprevisto',
      });
      expect(a.canceladoPor, CancelledBy.clinica);
      expect(a.cancelledByClinic, isTrue);
      expect(a.motivoCancelacion, 'Imprevisto');
      expect(Appointment.fromMap('a1', a.toMap()), a);
    });

    test('estado desconocido se trata como terminado (sin acciones)', () {
      final a = Appointment.fromMap('a1', {...doc, 'estado': 'nuevo_estado'});
      expect(a.estado.isFinal, isTrue);
      expect(a.ownerCanCancel(DateTime.utc(2026, 11, 1)), isFalse);
    });

    test('el dueño cancela hasta 2 h antes', () {
      final a = Appointment.fromMap('a1', doc);
      expect(a.ownerCanCancel(BogotaTime.at(2026, 11, 5, 7, 30)), isTrue);
      expect(a.ownerCanCancel(BogotaTime.at(2026, 11, 5, 7, 31)), isFalse);
      final done = a.copyWith(estado: AppointmentStatus.completada);
      expect(done.ownerCanCancel(BogotaTime.at(2026, 11, 1)), isFalse);
    });

    test('la clínica completa solo después del inicio', () {
      final a = Appointment.fromMap('a1', doc);
      expect(a.canComplete(BogotaTime.at(2026, 11, 5, 9, 29)), isFalse);
      expect(a.canComplete(inicio), isTrue);
      final pending = a.copyWith(estado: AppointmentStatus.pendiente);
      expect(pending.canComplete(BogotaTime.at(2026, 11, 5, 10)), isFalse);
    });
  });
}
