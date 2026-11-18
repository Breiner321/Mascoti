/// Rutas del plugin tienda (RF-07, RF-12). Otros plugins y el core (carrito
/// del encabezado, notificaciones) las escriben tal cual, sin importar este
/// archivo.
abstract final class TiendaRoutes {
  // Dueño
  static const store = '/tienda';
  static const productPattern = '/tienda/producto/:id';
  static const cart = '/tienda/carrito';
  static const ownerOrders = '/tienda/pedidos';
  static const orderPattern = '/tienda/pedidos/:id';

  // Clínica
  static const inventory = '/tienda/inventario';
  static const clinicOrders = '/tienda/clinica/pedidos';

  /// Un producto vive en `clinics/{clinicId}/products/{id}`: la ruta lleva
  /// la clínica como parámetro (`?clinicId=`).
  static String product(String clinicId, String productId) =>
      '/tienda/producto/$productId?clinicId=${Uri.encodeQueryComponent(clinicId)}';

  static String order(String orderId) => '/tienda/pedidos/$orderId';
}
