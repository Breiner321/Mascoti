import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/domain/cart_item.dart';
import 'package:mascoti/core/domain/product.dart';

void main() {
  final doc = <String, dynamic>{
    'clinicId': 'c1',
    'nombre': 'Concentrado 2 kg',
    'categoria': 'alimento',
    'descripcion': 'Perros adultos',
    'precio': 45000,
    'stock': 5,
    'stockReservado': 2,
    'fotoPath': 'vet/p1.jpg',
    'estado': 'activo',
    'createdAt': Timestamp.fromDate(DateTime(2026, 11, 1)),
    'updatedAt': Timestamp.fromDate(DateTime(2026, 11, 2)),
  };

  group('Product', () {
    test('fromMap lee los campos del RF-07', () {
      final p = Product.fromMap('p1', doc);
      expect(p.categoria, ProductCategory.alimento);
      expect(p.precio, 45000);
      expect(p.stock, 5);
      expect(p.stockReservado, 2);
      expect(p.available, 3);
      expect(p.isVisibleToOwners, isTrue);
    });

    test('toMap no incluye stockReservado ni createdAt (solo el servidor)', () {
      final map = Product.fromMap('p1', doc).toMap();
      expect(map.containsKey('stockReservado'), isFalse);
      expect(map.containsKey('createdAt'), isFalse);
      expect(map['categoria'], 'alimento');
    });

    test('copyWith ajusta el estado al stock: 0 → agotado, > 0 → activo', () {
      final p = Product.fromMap('p1', doc);
      expect(p.copyWith(stock: 0).estado, ProductStatus.agotado);
      expect(p.copyWith(stock: 0).copyWith(stock: 4).estado, ProductStatus.activo);
      final inactive = p.copyWith(estado: ProductStatus.inactivo);
      expect(inactive.copyWith(stock: 0).estado, ProductStatus.inactivo);
    });

    test('disponible nunca es negativo y es 0 si no está activo', () {
      expect(Product.fromMap('p1', {...doc, 'stockReservado': 9}).available, 0);
      expect(Product.fromMap('p1', {...doc, 'estado': 'inactivo'}).available, 0);
      expect(Product.fromMap('p1', {...doc, 'estado': 'inactivo'}).isVisibleToOwners, isFalse);
    });

    test('valores desconocidos', () {
      expect(ProductCategory.fromValue('ropa'), ProductCategory.accesorio);
      expect(ProductStatus.fromValue('raro'), ProductStatus.inactivo);
      expect(ProductCategory.medicamentoOtc.value, 'medicamento_otc');
    });
  });

  group('ProductValidators (RF-07 paso 5, iguales a firestore.rules)', () {
    test('nombre 3-60', () {
      expect(ProductValidators.nombre(''), isNotNull);
      expect(ProductValidators.nombre('Ab'), isNotNull);
      expect(ProductValidators.nombre('x' * 61), isNotNull);
      expect(ProductValidators.nombre('Collar'), isNull);
      expect(ProductValidators.nombre('x' * 60), isNull);
    });

    test('precio entero > 0', () {
      expect(ProductValidators.precio('0'), 'El precio debe ser mayor que 0');
      expect(ProductValidators.precio('45000.5'), isNotNull);
      expect(ProductValidators.precio('abc'), isNotNull);
      expect(ProductValidators.precio('45000'), isNull);
    });

    test('stock entero ≥ 0', () {
      expect(ProductValidators.stock('-1'), 'El stock no puede ser negativo');
      expect(ProductValidators.stock('1.5'), isNotNull);
      expect(ProductValidators.stock('0'), isNull);
    });

    test('descripción hasta 1000', () {
      expect(ProductValidators.descripcion('x' * 1001), isNotNull);
      expect(ProductValidators.descripcion(null), isNull);
    });
  });

  group('CartItem', () {
    test('fromMap, subtotal y totales de referencia', () {
      final item = CartItem.fromMap('p1', {
        'clinicId': 'c1',
        'nombre': 'Concentrado',
        'precio': 45000,
        'cantidad': 2,
        'addedAt': Timestamp.fromDate(DateTime(2026, 11, 18)),
      });
      expect(item.subtotal, 90000);
      expect(item.toMap(), {'clinicId': 'c1', 'nombre': 'Concentrado', 'precio': 45000, 'cantidad': 2});
      final other = item.copyWith(cantidad: 1, precio: 12000);
      expect(cartReferenceTotal([item, other]), 102000);
      expect(cartUnits([item, other]), 3);
      expect(CartItem.fromMap('p1', {...item.toMap(), 'addedAt': Timestamp.fromDate(DateTime(2026, 11, 18))}),
          item);
    });
  });
}
