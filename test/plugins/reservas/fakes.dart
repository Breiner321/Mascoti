import 'package:mascoti/core/auth/domain/app_user.dart';
import 'package:mascoti/core/domain/appointment.dart';
import 'package:mascoti/core/domain/clinic.dart';
import 'package:mascoti/core/domain/clinic_service.dart';
import 'package:mascoti/core/domain/pet.dart';
import 'package:mascoti/core/domain/slot.dart';
import 'package:mascoti/core/domain/weekly_schedule.dart';
import 'package:mascoti/core/format/bogota_time.dart';

const owner = AppUser(
  uid: 'ana',
  email: 'ana@example.com',
  displayName: 'Ana',
  role: UserRole.dueno,
);

/// Cambio 2: solo atiende los viernes de 9:00 a 11:00, en franjas de 30 min.
final clinic = Clinic(
  id: 'c1',
  ownerUid: 'vet',
  nombre: 'Clínica Norte',
  telefono: '6041234567',
  direccion: 'Calle 10 # 20-30',
  lat: 6.2,
  lng: -75.5,
  estado: ClinicStatus.activo,
  horarioSemanal: WeeklySchedule({
    for (final d in Weekday.values)
      d: d == Weekday.vie
          ? const DayHours(abierto: true, apertura: '09:00', cierre: '11:00')
          : const DayHours.closed(),
  }),
  reservas: const BookingSettings(),
);

const consulta = ClinicService(
  id: 's1',
  nombre: 'Consulta',
  categoria: ServiceCategory.consultaGeneral,
  precio: 45000,
  duracionMin: 30,
);

const vacuna = ClinicService(
  id: 's2',
  nombre: 'Vacuna',
  categoria: ServiceCategory.vacunacion,
  precio: 60000,
  duracionMin: 15,
);

const luna = Pet(id: 'p1', ownerUid: 'ana', nombre: 'Luna', especie: PetSpecies.perro);
const milo = Pet(id: 'p2', ownerUid: 'ana', nombre: 'Milo', especie: PetSpecies.gato);

Slot slot(String fecha, String hora, {String serviceId = 's1', SlotStatus? estado}) => Slot.at(
      fecha: fecha,
      hora: hora,
      estado: estado ?? SlotStatus.disponible,
      serviceId: serviceId,
      precio: 45000,
    );

Appointment appointment(
  String id, {
  required DateTime inicio,
  AppointmentStatus estado = AppointmentStatus.pendiente,
  String clinicId = 'c1',
  String clinicNombre = 'Clínica Norte',
  String? motivoRechazo,
}) {
  final w = BogotaTime.wallClock(inicio);
  return Appointment(
    id: id,
    clinicId: clinicId,
    clinicNombre: clinicNombre,
    ownerUid: 'ana',
    petId: 'p1',
    petNombre: 'Luna',
    serviceId: 's1',
    serviceNombre: 'Consulta',
    precioAcordado: 45000,
    slotId: '${BogotaTime.dateKey(inicio)}_${w.hour.toString().padLeft(2, '0')}:'
        '${w.minute.toString().padLeft(2, '0')}',
    fecha: BogotaTime.dateKey(inicio),
    hora: '${w.hour.toString().padLeft(2, '0')}:${w.minute.toString().padLeft(2, '0')}',
    inicio: inicio,
    estado: estado,
    motivoRechazo: motivoRechazo,
  );
}
