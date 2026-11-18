import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Categoría de un producto (RF-07). [value] se guarda en Firestore.
enum ProductCategory {
  alimento('alimento', 'Alimento'),
  juguete('juguete', 'Juguete'),
  accesorio('accesorio', 'Accesorio'),
  medicamentoOtc('medicamento_otc', 'Medicamento OTC');

  const ProductCategory(this.value, this.label);

  final String value;
  final String label;

  /// Un valor desconocido se muestra como "Accesorio".
  static ProductCategory fromValue(Object? value) {
    for (final c in values) {
      if (c.value == value) return c;
    }
    return accesorio;
  }
}

/// Estado de un producto (RF-07). `agotado` ⇔ `stock == 0` (salvo
/// `inactivo`, que es el borrado lógico): lo exigen las reglas.
enum ProductStatus {
  activo('activo', 'Activo'),
  agotado('agotado', 'Agotado'),
  inactivo('inactivo', 'Inactivo');

  const ProductStatus(this.value, this.label);

  final String value;
  final String label;

  static ProductStatus fromValue(Object? value) {
    for (final s in values) {
      if (s.value == value) return s;
    }
    return inactivo;
  }

  /// Estado que corresponde a [stock] para un producto que no está
  /// inactivo (RF-07 paso 10).
  static ProductStatus forStock(int stock) => stock == 0 ? agotado : activo;
}

/// Límites del formulario de producto (iguales a firestore.rules).
abstract final class ProductLimits {
  static const minNombre = 3;
  static const maxNombre = 60;
  static const maxDescripcion = 1000;
  static const maxPrecio = 100000000;
  static const maxStock = 100000;
}

/// Validaciones del formulario de producto (RF-07 paso 5). Devuelven el
/// mensaje de error o null si el valor es válido.
abstract final class ProductValidators {
  static String? nombre(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'El nombre es obligatorio';
    if (v.length < ProductLimits.minNombre || v.length > ProductLimits.maxNombre) {
      return 'El nombre debe tener entre ${ProductLimits.minNombre} y '
          '${ProductLimits.maxNombre} caracteres';
    }
    return null;
  }

  /// Precio en pesos, entero mayor que 0 (sin decimales).
  static String? precio(String? value) {
    final v = int.tryParse(value?.trim() ?? '');
    if (v == null) return 'Ingresa un precio en pesos, sin decimales';
    if (v <= 0) return 'El precio debe ser mayor que 0';
    if (v > ProductLimits.maxPrecio) return 'El precio es demasiado alto';
    return null;
  }

  /// Stock entero mayor o igual a 0.
  static String? stock(String? value) {
    final v = int.tryParse(value?.trim() ?? '');
    if (v == null) return 'Ingresa un número entero';
    if (v < 0) return 'El stock no puede ser negativo';
    if (v > ProductLimits.maxStock) return 'El stock es demasiado alto';
    return null;
  }

  static String? descripcion(String? value) =>
      (value?.trim().length ?? 0) > ProductLimits.maxDescripcion
          ? 'La descripción no puede superar ${ProductLimits.maxDescripcion} caracteres'
          : null;
}

/// Documento `clinics/{clinicId}/products/{productId}` (RF-07). No se borra:
/// se desactiva con `estado: 'inactivo'` (soft delete).
///
/// `stockReservado` lo escribe SOLO el servidor: unidades apartadas por
/// pedidos `pendiente_pago` (15 min). Lo que un dueño puede comprar es
/// [available] = `stock - stockReservado`.
@immutable
class Product {
  const Product({
    required this.id,
    required this.clinicId,
    required this.nombre,
    required this.categoria,
    required this.precio,
    required this.stock,
    required this.fotoPath,
    this.descripcion = '',
    this.stockReservado = 0,
    this.estado = ProductStatus.activo,
    this.createdAt,
    this.updatedAt,
  });

  factory Product.fromMap(String id, Map<String, dynamic> map) => Product(
        id: id,
        clinicId: map['clinicId'] as String? ?? '',
        nombre: map['nombre'] as String? ?? '',
        categoria: ProductCategory.fromValue(map['categoria']),
        descripcion: map['descripcion'] as String? ?? '',
        precio: (map['precio'] as num?)?.toInt() ?? 0,
        stock: (map['stock'] as num?)?.toInt() ?? 0,
        stockReservado: (map['stockReservado'] as num?)?.toInt() ?? 0,
        fotoPath: map['fotoPath'] as String? ?? '',
        estado: ProductStatus.fromValue(map['estado']),
        createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
        updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
      );

  final String id;
  final String clinicId;
  final String nombre;
  final ProductCategory categoria;
  final String descripcion;

  /// En pesos colombianos, entero (sin decimales).
  final int precio;

  /// Unidades físicas en la clínica.
  final int stock;

  /// Unidades apartadas por pagos en curso (solo el servidor lo cambia).
  final int stockReservado;

  /// Ruta en Supabase Storage (bucket `productos`), no una URL.
  final String fotoPath;
  final ProductStatus estado;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Unidades que un dueño puede agregar al carrito ahora.
  int get available {
    if (estado != ProductStatus.activo) return 0;
    final free = stock - stockReservado;
    return free < 0 ? 0 : free;
  }

  /// Se muestra en la tienda del dueño (activo o agotado).
  bool get isVisibleToOwners => estado != ProductStatus.inactivo;

  /// Mapa para crear o actualizar desde la app. No incluye
  /// `stockReservado` (solo el servidor lo escribe) ni `createdAt` (lo pone
  /// el repositorio con la hora del servidor al crear).
  Map<String, dynamic> toMap() => {
        'clinicId': clinicId,
        'nombre': nombre.trim(),
        'categoria': categoria.value,
        'descripcion': descripcion.trim(),
        'precio': precio,
        'stock': stock,
        'fotoPath': fotoPath,
        'estado': estado.value,
      };

  /// Copia. Si cambia el stock y no se indica el estado, el estado se
  /// ajusta solo (0 → agotado, > 0 → activo), salvo si está inactivo.
  Product copyWith({
    String? nombre,
    ProductCategory? categoria,
    String? descripcion,
    int? precio,
    int? stock,
    String? fotoPath,
    ProductStatus? estado,
  }) {
    final newStock = stock ?? this.stock;
    final newStatus = estado ??
        (this.estado == ProductStatus.inactivo
            ? ProductStatus.inactivo
            : ProductStatus.forStock(newStock));
    return Product(
      id: id,
      clinicId: clinicId,
      nombre: nombre ?? this.nombre,
      categoria: categoria ?? this.categoria,
      descripcion: descripcion ?? this.descripcion,
      precio: precio ?? this.precio,
      stock: newStock,
      stockReservado: stockReservado,
      fotoPath: fotoPath ?? this.fotoPath,
      estado: newStatus,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Product &&
      other.id == id &&
      other.clinicId == clinicId &&
      other.nombre == nombre &&
      other.categoria == categoria &&
      other.descripcion == descripcion &&
      other.precio == precio &&
      other.stock == stock &&
      other.stockReservado == stockReservado &&
      other.fotoPath == fotoPath &&
      other.estado == estado &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(id, clinicId, nombre, categoria, descripcion, precio, stock,
      stockReservado, fotoPath, estado, createdAt, updatedAt);
}
