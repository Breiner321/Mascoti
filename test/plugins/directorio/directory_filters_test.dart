import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/data/clinics_geo_repository.dart';
import 'package:mascoti/core/domain/animal_type.dart';
import 'package:mascoti/core/domain/clinic.dart';
import 'package:mascoti/core/domain/clinic_service.dart';
import 'package:mascoti/core/domain/weekly_schedule.dart';
import 'package:mascoti/core/format/bogota_time.dart';
import 'package:mascoti/plugins/directorio/domain/clinic_schedule.dart';
import 'package:mascoti/plugins/directorio/domain/directory_filters.dart';
import 'package:mascoti/plugins/directorio/presentation/clinic_public_profile_page.dart';

void main() {
  group('radio', () {
    test('por defecto 10 km (RF-09)', () {
      expect(const DirectoryFilters().radiusKm, 10);
    });

    test('el control deslizante queda entre 5 y 50 km, en km enteros', () {
      expect(DirectoryFilters.clampRadius(1), 5);
      expect(DirectoryFilters.clampRadius(80), 50);
      expect(DirectoryFilters.clampRadius(12.6), 13);
      expect(const DirectoryFilters().withRadius(70).radiusKm, 50);
    });
  });

  group('filtros', () {
    test('sin filtros no descarta ninguna clínica', () {
      const f = DirectoryFilters();
      expect(f.hasFilters, isFalse);
      expect(f.toClinicFilters(), const ClinicFilters());
    });

    test('tipo de animal se agrega y se quita', () {
      final f = const DirectoryFilters()
          .toggleAnimal(AnimalType.perros)
          .toggleAnimal(AnimalType.gatos)
          .toggleAnimal(AnimalType.perros);
      expect(f.animalTypes, {AnimalType.gatos});
      expect(f.activeCount, 1);
    });

    test('elegir el mismo servicio lo quita', () {
      final f = const DirectoryFilters().toggleService(ServiceCategory.peluqueria);
      expect(f.service, ServiceCategory.peluqueria);
      expect(f.toggleService(ServiceCategory.peluqueria).service, isNull);
      expect(f.toggleService(ServiceCategory.cirugia).service, ServiceCategory.cirugia);
    });

    test('"24 horas" son las clínicas con emergencias', () {
      final f = const DirectoryFilters().toggleEmergencies();
      expect(f.toClinicFilters().onlyEmergencies, isTrue);
    });

    test('se combinan en ClinicFilters y "Quitar filtros" conserva el radio', () {
      final f = const DirectoryFilters()
          .toggleAnimal(AnimalType.perros)
          .toggleService(ServiceCategory.vacunacion)
          .toggleEmergencies()
          .withRadius(20);

      expect(f.activeCount, 3);
      expect(
        f.toClinicFilters(),
        const ClinicFilters(
          animalTypes: {AnimalType.perros},
          serviceCategory: ServiceCategory.vacunacion,
          onlyEmergencies: true,
        ),
      );
      expect(f.cleared(), const DirectoryFilters(radiusKm: 20));
    });

    test('los filtros convertidos descartan lo que no cumple', () {
      const perros = Clinic(
        id: 'a',
        ownerUid: 'o',
        nombre: 'Vet Perros',
        telefono: '',
        direccion: '',
        lat: 0,
        lng: 0,
        tiposAnimales: [AnimalType.perros],
        categoriasServicio: [ServiceCategory.peluqueria],
      );
      final f = const DirectoryFilters().toggleAnimal(AnimalType.perros);
      expect(f.toClinicFilters().matches(perros), isTrue);
      expect(f.toggleAnimal(AnimalType.gatos).toClinicFilters().matches(perros), isFalse);
      expect(f.toggleEmergencies().toClinicFilters().matches(perros), isFalse);
    });
  });

  test('distancia: metros bajo 1 km y coma decimal', () {
    expect(distanceLabel(0.85), '850 m');
    expect(distanceLabel(2.34), '2,3 km');
    expect(distanceLabel(12.6), '13 km');
  });

  test('"Cómo llegar" y "Llamar" no necesitan API key', () {
    const clinic = Clinic(
      id: 'c1',
      ownerUid: 'o',
      nombre: 'Vet Norte',
      telefono: '604 123 4567',
      direccion: '',
      lat: 6.2,
      lng: -75.5,
    );
    expect(ClinicPublicProfilePage.directionsUri(clinic).toString(),
        'geo:6.2,-75.5?q=6.2,-75.5(Vet%20Norte)');
    expect(ClinicPublicProfilePage.osmDirectionsUri(clinic).host, 'www.openstreetmap.org');
    expect(ClinicPublicProfilePage.callUri(clinic.telefono).toString(), 'tel:6041234567');
  });

  group('abierto o cerrado según el horario semanal (hora de Colombia)', () {
    // Lunes a sábado 8–18 con almuerzo 12–14; domingo cerrado.
    final schedule = WeeklySchedule.standard;

    test('abierto, almuerzo y cierre', () {
      // 19 de octubre de 2026 es lunes.
      expect(openLabel(schedule, BogotaTime.at(2026, 10, 19, 9)), 'Abierto');
      expect(openLabel(schedule, BogotaTime.at(2026, 10, 19, 12, 30)), 'Cerrado');
      expect(openLabel(schedule, BogotaTime.at(2026, 10, 19, 14)), 'Abierto');
      expect(openLabel(schedule, BogotaTime.at(2026, 10, 19, 18)), 'Cerrado');
      expect(openLabel(schedule, BogotaTime.at(2026, 10, 19, 7, 59)), 'Cerrado');
      expect(openLabel(schedule, BogotaTime.at(2026, 10, 25, 10)), 'Cerrado');
      expect(openLabel(null, BogotaTime.at(2026, 10, 19, 9)), isNull);
    });

    test('usa la hora de Colombia aunque el teléfono esté en otra zona', () {
      // 13:30 UTC = 8:30 a. m. en Bogotá.
      expect(openLabel(schedule, DateTime.utc(2026, 10, 19, 13, 30)), 'Abierto');
      expect(openLabel(schedule, DateTime.utc(2026, 10, 19, 12, 30)), 'Cerrado');
    });

    test('horario de hoy', () {
      expect(todayHoursLabel(schedule, BogotaTime.at(2026, 10, 19, 9)), contains(' · '));
      expect(todayHoursLabel(schedule, BogotaTime.at(2026, 10, 25, 9)), 'Hoy no atiende');
      expect(todayHoursLabel(null, BogotaTime.at(2026, 10, 19, 9)), isNull);
    });
  });

  test('"Solo aliados" (Cambio 4)', () {
    const f = DirectoryFilters();
    final only = f.toggleOnlyAllies();
    expect(only.onlyAllies, isTrue);
    expect(only.activeCount, 1);
    expect(only.hasAllyOnlyFilters, isFalse);
    expect(only.cleared().onlyAllies, isFalse);
    expect(only.toggleEmergencies().hasAllyOnlyFilters, isTrue);
    expect(only.toggleService(ServiceCategory.values.first).onlyAllies, isTrue);
    expect(only.withRadius(20).onlyAllies, isTrue);
    expect(only, isNot(f));
  });
}
