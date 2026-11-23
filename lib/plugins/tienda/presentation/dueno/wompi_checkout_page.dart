import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../../core/data/shop_repository.dart';
import '../../tienda_routes.dart';

/// Web Checkout de Wompi (sandbox) en un WebView (RF-12). Se cierra al
/// llegar a la URL de regreso y lleva al detalle del pedido, que espera la
/// confirmación del webhook: la URL de regreso NUNCA se toma como pago
/// aprobado.
class WompiCheckoutPage extends StatefulWidget {
  const WompiCheckoutPage({
    super.key,
    required this.orderId,
    required this.checkoutUrl,
    required this.redirectUrl,
  });

  final String orderId;
  final String checkoutUrl;
  final String redirectUrl;

  @override
  State<WompiCheckoutPage> createState() => _WompiCheckoutPageState();
}

class _WompiCheckoutPageState extends State<WompiCheckoutPage> {
  late final WebViewController _controller;
  int _progress = 0;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        onNavigationRequest: (request) {
          if (ShopRepository.isCheckoutReturn(
              request.url, widget.redirectUrl)) {
            _finish();
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
        onUrlChange: (change) {
          final url = change.url;
          if (url != null &&
              ShopRepository.isCheckoutReturn(url, widget.redirectUrl)) {
            _finish();
          }
        },
      ))
      ..loadRequest(Uri.parse(widget.checkoutUrl));
  }

  /// Cierra el pago y muestra el pedido (que dice si se confirmó).
  void _finish() {
    if (_done || !mounted) return;
    _done = true;
    context.go(TiendaRoutes.order(widget.orderId));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pagar con Wompi'),
        leading: IconButton(
          tooltip: 'Cerrar el pago',
          icon: const Icon(Icons.close),
          onPressed: _finish,
        ),
      ),
      body: Column(
        children: [
          if (_progress < 100) LinearProgressIndicator(value: _progress / 100),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }
}
