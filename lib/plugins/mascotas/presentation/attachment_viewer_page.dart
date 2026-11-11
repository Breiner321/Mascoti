import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Imagen adjunta a pantalla completa, con zoom (pellizcar o doble toque).
class AttachmentViewerPage extends StatefulWidget {
  const AttachmentViewerPage({super.key, required this.title, required this.url});

  final String title;
  final String url;

  @override
  State<AttachmentViewerPage> createState() => _AttachmentViewerPageState();
}

class _AttachmentViewerPageState extends State<AttachmentViewerPage> {
  final _controller = TransformationController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleZoom() {
    _controller.value = _controller.value.getMaxScaleOnAxis() > 1
        ? Matrix4.identity()
        : (Matrix4.identity()..scaleByDouble(2.5, 2.5, 1, 1));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.textPrimary,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        foregroundColor: AppColors.onPrimary,
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: GestureDetector(
        onDoubleTap: _toggleZoom,
        child: InteractiveViewer(
          transformationController: _controller,
          minScale: 1,
          maxScale: 5,
          child: Center(
            child: Image.network(
              widget.url,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : CircularProgressIndicator(color: AppColors.onPrimary),
              errorBuilder: (_, __, ___) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.broken_image_outlined, color: AppColors.onPrimary, size: 48),
                  const SizedBox(height: 8),
                  Text('Archivo no disponible', style: TextStyle(color: AppColors.onPrimary)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
