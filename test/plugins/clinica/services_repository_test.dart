import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/domain/clinic_service.dart';
import 'package:mascoti/plugins/clinica/data/services_repository.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late ServicesRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = ServicesRepository(firestore: firestore);
  });

  ClinicService service(String id, {String nombre = 'Consulta general'}) => ClinicService(
        id: id,
        nombre: nombre,
        categoria: ServiceCategory.consultaGeneral,
        descripcion: 'Revisión completa',
        precio: 45000,
        duracionMin: 30,
      );

  Future<Map<String, dynamic>> read(String id) async =>
      (await firestore.doc('clinics/c1/services/$id').get()).data()!;

  test('crear: guarda el servicio activo con sus fechas', () async {
    final id = repo.newId('c1');
    await repo.save('c1', service(id), isNew: true);

    final data = await read(id);
    expect(data['nombre'], 'Consulta general');
    expect(data['categoria'], 'consulta_general');
    expect(data['descripcion'], 'Revisión completa');
    expect(data['precio'], 45000);
    expect(data['duracionMin'], 30);
    expect(data['activo'], isTrue);
    expect(data['createdAt'], isA<Timestamp>());
    expect(data['updatedAt'], isA<Timestamp>());
  });

  test('crear dos veces con el mismo id no duplica (reintento)', () async {
    final id = repo.newId('c1');
    await repo.save('c1', service(id), isNew: true);
    await repo.save('c1', service(id), isNew: true);

    final docs = await firestore.collection('clinics/c1/services').get();
    expect(docs.size, 1);
  });

  test('editar: cambia los campos editables y conserva createdAt y activo', () async {
    final id = repo.newId('c1');
    await repo.save('c1', service(id), isNew: true);
    final createdAt = (await read(id))['createdAt'];

    await repo.save(
      'c1',
      service(id).copyWith(nombre: 'Consulta especializada', precio: 60000),
      isNew: false,
    );

    final data = await read(id);
    expect(data['nombre'], 'Consulta especializada');
    expect(data['precio'], 60000);
    expect(data['createdAt'], createdAt);
    expect(data['activo'], isTrue);
  });

  test('borrado lógico: el documento sigue existiendo con activo = false', () async {
    final id = repo.newId('c1');
    await repo.save('c1', service(id), isNew: true);

    await repo.deactivate('c1', id);

    final data = await read(id);
    expect(data['activo'], isFalse);
    expect(data['nombre'], 'Consulta general');
  });

  test('watchActive: solo activos, ordenados por nombre y en tiempo real', () async {
    await repo.save('c1', service('a', nombre: 'Vacunación'), isNew: true);
    await repo.save('c1', service('b', nombre: 'baño'), isNew: true);
    await repo.save('c1', service('c', nombre: 'Cirugía'), isNew: true);

    final emitted = <List<ClinicService>>[];
    final sub = repo.watchActive('c1').listen(emitted.add);
    await pumpEventQueue();
    expect(emitted.last.map((s) => s.nombre), ['baño', 'Cirugía', 'Vacunación']);

    await repo.deactivate('c1', 'c');
    await pumpEventQueue();
    await sub.cancel();
    expect(emitted.last.map((s) => s.id), ['b', 'a']);
  });

  test('watchActive no mezcla servicios de otra clínica', () async {
    await repo.save('c2', service('x'), isNew: true);
    expect(await repo.watchActive('c1').first, isEmpty);
  });

  test('mantiene en la clínica las categorías de sus servicios activos (RF-09)', () async {
    await firestore.doc('clinics/c1').set({'nombre': 'Vet', 'estado': 'activo'});
    Future<List<dynamic>?> categorias() async =>
        (await firestore.doc('clinics/c1').get()).data()!['categoriasServicio'] as List?;

    await repo.save('c1', service('a'), isNew: true);
    await repo.save(
      'c1',
      service('b', nombre: 'Baño').copyWith(categoria: ServiceCategory.bano),
      isNew: true,
    );
    expect(await categorias(), ['bano', 'consulta_general']);

    await repo.deactivate('c1', 'b');
    expect(await categorias(), ['consulta_general']);
  });

  test('citas activas: 0 hasta que existan las citas (RF-14)', () async {
    expect(await repo.activeAppointmentsCount('c1', 'a'), 0);
  });
}
