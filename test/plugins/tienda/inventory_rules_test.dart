import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/data/shop_repository.dart';
import 'package:mascoti/core/domain/product.dart';
import 'package:mascoti/plugins/tienda/domain/inventory_rules.dart';
import 'package:mascoti/plugins/tienda/presentation/comun/price_format.dart';

Product product(
  String id,
  String nombre, {
  int stock = 10,
  ProductStatus? estado,
}) =>
    Product(
      id: id,
      clinicId: 'c1',
      nombre: nombre,
      categoria: ProductCategory.alimento,
      precio: 45000,
      stock: stock,
      fotoPath: 'vet/$id.jpg',
      estado: estado ?? ProductStatus.forStock(stock),
    );

void main() {
  group('stock bajo', () {
    test('entre 1 y 3 unidades de un producto publicado', () {
      expect(InventoryRules.isLowStock(product('a', 'A', stock: 1)), isTrue);
      expect(InventoryRules.isLowStock(product('a', 'A', stock: 3)), isTrue);
      expect(InventoryRules.isLowStock(product('a', 'A', stock: 4)), isFalse);
    });

    test('agotado (0) o inactivo no cuentan como stock bajo', () {
      expect(InventoryRules.isLowStock(product('a', 'A', stock: 0)), isFalse);
      expect(
        InventoryRules.isLowStock(product('a', 'A', stock: 2, estado: ProductStatus.inactivo)),
        isFalse,
      );
    });
  });

  group('agotado', () {
    test('se aplica solo con stock 0 y se quita al reponer', () {
      expect(InventoryRules.statusAfterStock(ProductStatus.activo, 0), ProductStatus.agotado);
      expect(InventoryRules.statusAfterStock(ProductStatus.activo, 1), ProductStatus.activo);
      expect(InventoryRules.statusAfterStock(ProductStatus.agotado, 5), ProductStatus.activo);
    });

    test('un producto inactivo sigue inactivo aunque cambie el stock', () {
      expect(InventoryRules.statusAfterStock(ProductStatus.inactivo, 0), ProductStatus.inactivo);
      expect(InventoryRules.statusAfterStock(ProductStatus.inactivo, 8), ProductStatus.inactivo);
    });

    test('los botones +/− ponen y quitan "agotado" en Firestore', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = ShopRepository(firestore: firestore);
      await repo.createProduct(product('p1', 'Collar', stock: 1));

      await repo.adjustStock('c1', 'p1', -1);
      var doc = (await firestore.doc('clinics/c1/products/p1').get()).data()!;
      expect(doc['stock'], 0);
      expect(doc['estado'], 'agotado');

      await repo.adjustStock('c1', 'p1', 1);
      doc = (await firestore.doc('clinics/c1/products/p1').get()).data()!;
      expect(doc['stock'], 1);
      expect(doc['estado'], 'activo');

      await repo.adjustStock('c1', 'p1', -1);
      expect(
        () => repo.adjustStock('c1', 'p1', -1),
        throwsA(isA<ShopFailure>()),
      );
    });
  });

  group('filtro y búsqueda', () {
    final all = [
      product('a', 'Collar antipulgas'),
      product('b', 'Concentrado cachorro', stock: 0),
      product('c', 'Pelota', stock: 2),
      product('d', 'Champú', stock: 5, estado: ProductStatus.inactivo),
    ];

    test('por estado', () {
      List<String> ids(InventoryFilter f) =>
          InventoryRules.filter(all, filter: f).map((p) => p.id).toList();
      expect(ids(InventoryFilter.todos), ['a', 'b', 'c', 'd']);
      expect(ids(InventoryFilter.activo), ['a', 'c']);
      expect(ids(InventoryFilter.agotado), ['b']);
      expect(ids(InventoryFilter.inactivo), ['d']);
      expect(ids(InventoryFilter.stockBajo), ['c']);
    });

    test('por nombre, sin mayúsculas ni tildes', () {
      expect(InventoryRules.filter(all, query: 'CHAMPU').single.id, 'd');
      expect(InventoryRules.filter(all, query: ' col ').single.id, 'a');
      expect(InventoryRules.filter(all, query: 'gato'), isEmpty);
    });
  });

  group('producto duplicado (> 85 %)', () {
    final inventory = [product('a', 'Collar antipulgas'), product('b', 'Pelota')];

    test('advierte un nombre muy parecido', () {
      expect(InventoryRules.similarProduct('collar antipulga', inventory)?.id, 'a');
      expect(InventoryRules.similarProduct('Collar Antipulgas', inventory)?.id, 'a');
    });

    test('no advierte nombres distintos ni el mismo producto al editar', () {
      expect(InventoryRules.similarProduct('Collar grande', inventory), isNull);
      expect(
        InventoryRules.similarProduct('Collar antipulgas', inventory, excludeId: 'a'),
        isNull,
      );
    });

    test('similitud entre 0 y 1', () {
      expect(InventoryRules.nameSimilarity('Pelota', 'pelota'), 1);
      expect(InventoryRules.nameSimilarity('abc', 'xyz'), 0);
    });
  });

  test('precio con separador de miles', () {
    expect(formatCop(45000), r'$ 45.000');
    expect(formatCop(1250000), r'$ 1.250.000');
  });
}
