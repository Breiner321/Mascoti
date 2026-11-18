import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Tipo de entrega de un pedido (RF-12).
enum DeliveryType {
  recoger('recoger', 'Recoger en la clínica'),
  domicilio('domicilio', 'Domicilio');

  const DeliveryType(this.value, this.label);

  final String value;
  final String label;

  static DeliveryType fromValue(Object? value) =>
      value == domicilio.value ? domicilio : recoger;
}

/// Estado de un pedido (RF-12). [value] se guarda en Firestore.
///
/// Máquina de estados igual a `supabase/functions/_shared/estados_pedido.ts`;
/// las dos pasan los casos de `test/fixtures/estados_pedido.json`. Solo el
/// servidor cambia el estado; la app lo usa para decidir qué botones mostrar.
///
/// ```
/// pendiente_pago → pagado | pago_rechazado | expirado        (webhook / tarea)
/// pagado         → preparando | cancelado                    (clínica)
/// preparando     → listo (recoger) | enviado (domicilio) | cancelado
/// listo | enviado → entregado
/// ```
enum OrderStatus {
  pendientePago('pendiente_pago', 'Pendiente de pago'),
  pagado('pagado', 'Pagado'),
  pagoRechazado('pago_rechazado', 'Pago rechazado'),
  expirado('expirado', 'Expirado'),
  preparando('preparando', 'En preparación'),
  listo('listo', 'Listo para recoger'),
  enviado('enviado', 'Enviado'),
  entregado('entregado', 'Entregado'),
  cancelado('cancelado', 'Cancelado');

  const OrderStatus(this.value, this.label);

  final String value;
  final String label;

  /// null si el valor no es un estado conocido.
  static OrderStatus? fromValue(Object? value) {
    for (final s in values) {
      if (s.value == value) return s;
    }
    return null;
  }

  /// true si un pedido en este estado con entrega [delivery] puede pasar a
  /// [to]. `listo` solo aplica a recoger y `enviado` solo a domicilio.
  bool canTransitionTo(OrderStatus to, DeliveryType delivery) {
    if (!_orderTransitions[this]!.contains(to)) return false;
    // `listo` solo existe para recoger y `enviado` solo para domicilio
    // (como origen y como destino).
    bool fits(OrderStatus s) =>
        (s != listo || delivery == DeliveryType.recoger) &&
        (s != enviado || delivery == DeliveryType.domicilio);
    return fits(this) && fits(to);
  }

  /// Siguientes estados posibles para [delivery].
  Set<OrderStatus> nextStates(DeliveryType delivery) => {
        for (final s in _orderTransitions[this]!)
          if (canTransitionTo(s, delivery)) s,
      };

  /// Ya no cambia (pago rechazado, expirado, entregado, cancelado).
  bool get isFinal => _orderTransitions[this]!.isEmpty;

  /// Estados que pone la clínica con `actualizar-pedido`.
  bool get isSetByClinic => _clinicStatuses.contains(this);

  /// Pedidos que la clínica puede ver (ya pagados). Las reglas solo le dejan
  /// leer estos.
  static const visibleToClinic = [pagado, preparando, listo, enviado, entregado, cancelado];
}

const _orderTransitions = <OrderStatus, Set<OrderStatus>>{
  OrderStatus.pendientePago: {OrderStatus.pagado, OrderStatus.pagoRechazado, OrderStatus.expirado},
  OrderStatus.pagado: {OrderStatus.preparando, OrderStatus.cancelado},
  OrderStatus.pagoRechazado: {},
  OrderStatus.expirado: {},
  OrderStatus.preparando: {OrderStatus.listo, OrderStatus.enviado, OrderStatus.cancelado},
  OrderStatus.listo: {OrderStatus.entregado},
  OrderStatus.enviado: {OrderStatus.entregado},
  OrderStatus.entregado: {},
  OrderStatus.cancelado: {},
};

const _clinicStatuses = {
  OrderStatus.preparando,
  OrderStatus.listo,
  OrderStatus.enviado,
  OrderStatus.entregado,
  OrderStatus.cancelado,
};

/// Límites de la entrega (iguales a `crear-pedido`).
abstract final class OrderLimits {
  static const minDireccion = 5;
  static const maxDireccion = 200;
  static const maxMotivo = 300;

  /// Minutos que se aparta el stock mientras el dueño paga.
  static const reservaMin = 15;
}

/// Datos de entrega: `{tipo, direccion?, telefono}`.
@immutable
class OrderDelivery {
  const OrderDelivery({required this.tipo, required this.telefono, this.direccion});

  factory OrderDelivery.fromMap(Map<String, dynamic> map) => OrderDelivery(
        tipo: DeliveryType.fromValue(map['tipo']),
        telefono: map['telefono'] as String? ?? '',
        direccion: map['direccion'] as String?,
      );

  final DeliveryType tipo;

  /// Obligatoria a domicilio (5–200 caracteres).
  final String? direccion;

  /// 10 dígitos.
  final String telefono;

  Map<String, dynamic> toMap() => {
        'tipo': tipo.value,
        if (tipo == DeliveryType.domicilio) 'direccion': direccion?.trim() ?? '',
        'telefono': telefono.trim(),
      };

  /// Mensaje de error o null si es válida (mismos textos que el servidor).
  String? validate() {
    if (!RegExp(r'^\d{10}$').hasMatch(telefono.trim())) {
      return 'El teléfono debe tener 10 dígitos';
    }
    if (tipo == DeliveryType.domicilio) {
      final d = direccion?.trim() ?? '';
      if (d.length < OrderLimits.minDireccion || d.length > OrderLimits.maxDireccion) {
        return 'Escribe la dirección de entrega (entre ${OrderLimits.minDireccion} y '
            '${OrderLimits.maxDireccion} caracteres)';
      }
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is OrderDelivery &&
      other.tipo == tipo &&
      other.direccion == direccion &&
      other.telefono == telefono;

  @override
  int get hashCode => Object.hash(tipo, direccion, telefono);
}

/// Producto de un pedido: copia del nombre y el precio que cobró el servidor.
@immutable
class OrderItem {
  const OrderItem({
    required this.productId,
    required this.nombre,
    required this.precio,
    required this.cantidad,
  });

  factory OrderItem.fromMap(Map<String, dynamic> map) => OrderItem(
        productId: map['productId'] as String? ?? '',
        nombre: map['nombre'] as String? ?? '',
        precio: (map['precio'] as num?)?.toInt() ?? 0,
        cantidad: (map['cantidad'] as num?)?.toInt() ?? 0,
      );

  final String productId;
  final String nombre;
  final int precio;
  final int cantidad;

  int get subtotal => precio * cantidad;

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'nombre': nombre,
        'precio': precio,
        'cantidad': cantidad,
      };

  @override
  bool operator ==(Object other) =>
      other is OrderItem &&
      other.productId == productId &&
      other.nombre == nombre &&
      other.precio == precio &&
      other.cantidad == cantidad;

  @override
  int get hashCode => Object.hash(productId, nombre, precio, cantidad);
}

/// Documento `orders/{orderId}` (RF-12). Lo crean y lo cambian SOLO las
/// Edge Functions (`crear-pedido`, `webhook-wompi`, `actualizar-pedido` y la
/// tarea programada); las reglas no dejan escribirlo desde la app.
@immutable
class ShopOrder {
  const ShopOrder({
    required this.id,
    required this.ownerUid,
    required this.ownerNombre,
    required this.clinicId,
    required this.clinicNombre,
    required this.items,
    required this.total,
    required this.entrega,
    required this.estado,
    required this.referenciaPago,
    this.wompiTransactionId,
    this.motivoCancelacion,
    this.pagoTardio = false,
    this.expiraEn,
    this.createdAt,
    this.updatedAt,
  });

  factory ShopOrder.fromMap(String id, Map<String, dynamic> map) => ShopOrder(
        id: id,
        ownerUid: map['ownerUid'] as String? ?? '',
        ownerNombre: map['ownerNombre'] as String? ?? '',
        clinicId: map['clinicId'] as String? ?? '',
        clinicNombre: map['clinicNombre'] as String? ?? '',
        items: [
          for (final item in (map['items'] as List?) ?? const [])
            if (item is Map) OrderItem.fromMap(Map<String, dynamic>.from(item)),
        ],
        total: (map['total'] as num?)?.toInt() ?? 0,
        entrega: OrderDelivery.fromMap(
          Map<String, dynamic>.from((map['entrega'] as Map?) ?? const {}),
        ),
        estado: OrderStatus.fromValue(map['estado']) ?? OrderStatus.pendientePago,
        referenciaPago: map['referenciaPago'] as String? ?? '',
        wompiTransactionId: map['wompiTransactionId'] as String?,
        motivoCancelacion: map['motivoCancelacion'] as String?,
        pagoTardio: map['pagoTardio'] == true,
        expiraEn: (map['expiraEn'] as Timestamp?)?.toDate(),
        createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
        updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
      );

  final String id;
  final String ownerUid;

  /// Copia al crear el pedido (la clínica no puede leer `users`).
  final String ownerNombre;
  final String clinicId;
  final String clinicNombre;
  final List<OrderItem> items;

  /// En pesos, calculado por el servidor con los precios de Firestore.
  final int total;
  final OrderDelivery entrega;
  final OrderStatus estado;

  /// Referencia única enviada a Wompi (`MSC-{orderId}`).
  final String referenciaPago;
  final String? wompiTransactionId;
  final String? motivoCancelacion;

  /// Wompi aprobó el pago después de que el pedido expiró: la clínica debe
  /// comunicarse con el dueño para el reembolso.
  final bool pagoTardio;

  /// Hasta cuándo se aparta el stock mientras el dueño paga.
  final DateTime? expiraEn;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  int get units => items.fold(0, (total, item) => total + item.cantidad);

  /// Mapa con los mismos campos que escribe el servidor (para pruebas).
  Map<String, dynamic> toMap() => {
        'ownerUid': ownerUid,
        'ownerNombre': ownerNombre,
        'clinicId': clinicId,
        'clinicNombre': clinicNombre,
        'items': [for (final item in items) item.toMap()],
        'total': total,
        'entrega': entrega.toMap(),
        'estado': estado.value,
        'referenciaPago': referenciaPago,
        if (wompiTransactionId != null) 'wompiTransactionId': wompiTransactionId,
        if (motivoCancelacion != null) 'motivoCancelacion': motivoCancelacion,
        if (pagoTardio) 'pagoTardio': true,
        if (expiraEn != null) 'expiraEn': Timestamp.fromDate(expiraEn!),
        if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
        if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
      };

  ShopOrder copyWith({OrderStatus? estado, String? motivoCancelacion}) => ShopOrder(
        id: id,
        ownerUid: ownerUid,
        ownerNombre: ownerNombre,
        clinicId: clinicId,
        clinicNombre: clinicNombre,
        items: items,
        total: total,
        entrega: entrega,
        estado: estado ?? this.estado,
        referenciaPago: referenciaPago,
        wompiTransactionId: wompiTransactionId,
        motivoCancelacion: motivoCancelacion ?? this.motivoCancelacion,
        pagoTardio: pagoTardio,
        expiraEn: expiraEn,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  @override
  bool operator ==(Object other) =>
      other is ShopOrder &&
      other.id == id &&
      other.ownerUid == ownerUid &&
      other.ownerNombre == ownerNombre &&
      other.clinicId == clinicId &&
      other.clinicNombre == clinicNombre &&
      listEquals(other.items, items) &&
      other.total == total &&
      other.entrega == entrega &&
      other.estado == estado &&
      other.referenciaPago == referenciaPago &&
      other.wompiTransactionId == wompiTransactionId &&
      other.motivoCancelacion == motivoCancelacion &&
      other.pagoTardio == pagoTardio &&
      other.expiraEn == expiraEn &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(id, ownerUid, ownerNombre, clinicId, clinicNombre,
      Object.hashAll(items), total, entrega, estado, referenciaPago, wompiTransactionId,
      motivoCancelacion, pagoTardio, expiraEn, createdAt, updatedAt);
}
