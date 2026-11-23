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

  /// Pantalla de pago de prueba: el checkout navega aquí cuando
  /// `CheckoutSession.isSimulated` (pagos ficticios, sin pasarela).
  static const payOrderPattern = '/tienda/pedidos/:id/pagar';

  // Clínica
  static const inventory = '/tienda/inventario';
  static const newProduct = '/tienda/inventario/nuevo';
  static const editProductPattern = '/tienda/inventario/:id/editar';
  static const clinicOrders = '/tienda/clinica/pedidos';
  static const clinicOrderPattern = '/tienda/clinica/pedidos/:id';

  /// Un producto vive en `clinics/{clinicId}/products/{id}`: la ruta lleva
  /// la clínica como parámetro (`?clinicId=`).
  static String product(String clinicId, String productId) =>
      '/tienda/producto/$productId?clinicId=${Uri.encodeQueryComponent(clinicId)}';

  static String order(String orderId) => '/tienda/pedidos/$orderId';

  static String payOrder(String orderId) => '/tienda/pedidos/$orderId/pagar';

  static String editProduct(String productId) => '/tienda/inventario/$productId/editar';

  static String clinicOrder(String orderId) => '/tienda/clinica/pedidos/$orderId';
}
