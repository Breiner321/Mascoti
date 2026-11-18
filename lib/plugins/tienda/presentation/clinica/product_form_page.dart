import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/auth_providers.dart';
import '../../../../core/data/shop_providers.dart';
import '../../../../core/domain/product.dart';
import '../../../../core/images/photo_compression.dart';
import '../../../../core/storage/storage_providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/inventory_rules.dart';
import '../comun/shop_message.dart';
import 'clinic_shop_providers.dart';
import 'product_photo_field.dart';

/// Crear ([productId] null) o editar un producto del inventario (RF-07).
class ProductFormPage extends ConsumerWidget {
  const ProductFormPage({super.key, this.productId});

  final String? productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = productId;
    if (id == null) return const _ProductForm(initial: null);

    final clinicId = ref.watch(currentUserProvider)?.clinicId ?? '';
    final product = ref.watch(productProvider((clinicId: clinicId, productId: id)));
    final Widget body = switch (product) {
      // Se toma el producto una sola vez: los cambios que lleguen después
      // (ventas) no deben borrar lo que la clínica está escribiendo.
      AsyncValue(:final Product value) => _ProductForm(key: ValueKey(id), initial: value),
      AsyncData() => const ShopMessage(
          icon: Icons.search_off,
          text: 'No encontramos este producto.',
        ),
      AsyncError() => ShopMessage(
          icon: Icons.cloud_off,
          text: 'No pudimos cargar el producto. Verifica tu conexión.',
          action: FilledButton(
            onPressed: () => ref.invalidate(productProvider((clinicId: clinicId, productId: id))),
            child: const Text('Reintentar'),
          ),
        ),
      _ => const Center(child: CircularProgressIndicator()),
    };
    if (body is _ProductForm) return body;
    return Scaffold(appBar: AppBar(title: const Text('Editar producto')), body: body);
  }
}

/// Etapas del guardado que se muestran sobre el botón.
enum _Stage {
  uploadingPhoto('Subiendo foto…'),
  saving('Guardando…');

  const _Stage(this.label);

  final String label;
}

class _ProductForm extends ConsumerStatefulWidget {
  const _ProductForm({super.key, required this.initial});

  /// null = producto nuevo.
  final Product? initial;

  @override
  ConsumerState<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends ConsumerState<_ProductForm> {
  final _formKey = GlobalKey<FormState>();
  late final _nombre = TextEditingController(text: widget.initial?.nombre);
  late final _descripcion = TextEditingController(text: widget.initial?.descripcion);
  late final _precio = TextEditingController(text: widget.initial?.precio.toString());
  late final _stock = TextEditingController(text: widget.initial?.stock.toString());
  late ProductCategory? _categoria = widget.initial?.categoria;

  PickedPhoto? _photo;
  bool _processingPhoto = false;
  String? _photoError;

  /// Ruta de la foto ya subida en este guardado (para no subirla otra vez
  /// al reintentar si lo que falló fue Firestore).
  String? _uploadedPath;

  /// Id del producto nuevo (se reserva antes de subir la foto).
  String? _newId;
  _Stage? _stage;

  /// Error del último guardado, con "Reintentar".
  String? _saveError;

  bool get _isNew => widget.initial == null;
  bool get _busy => _stage != null;

  @override
  void dispose() {
    _nombre.dispose();
    _descripcion.dispose();
    _precio.dispose();
    _stock.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(PhotoSource source) async {
    setState(() {
      _processingPhoto = true;
      _photoError = null;
    });
    try {
      final photo = await ref.read(productPhotoPickerProvider).pick(source);
      if (!mounted || photo == null) return;
      setState(() {
        _photo = photo;
        _uploadedPath = null;
      });
    } on PhotoException catch (e) {
      if (mounted) setState(() => _photoError = e.message);
    } catch (_) {
      if (mounted) setState(() => _photoError = 'No se pudo abrir la foto. Elige otra.');
    } finally {
      if (mounted) setState(() => _processingPhoto = false);
    }
  }

  Future<void> _save() async {
    final formOk = _formKey.currentState!.validate();
    final missingPhoto = _isNew && _photo == null;
    if (missingPhoto) setState(() => _photoError = 'Agrega una foto del producto');
    if (!formOk || missingPhoto) return;

    final user = ref.read(currentUserProvider);
    final clinicId = user?.clinicId;
    if (user == null || clinicId == null) return;
    final repo = ref.read(shopRepositoryProvider);
    final id = widget.initial?.id ?? (_newId ??= repo.newProductId(clinicId));

    setState(() => _saveError = null);
    final photo = _photo;
    if (photo != null && _uploadedPath == null) {
      setState(() => _stage = _Stage.uploadingPhoto);
      try {
        _uploadedPath = await ref.read(storageRepositoryProvider).uploadProductPhoto(
              clinicUid: user.uid,
              productId: id,
              bytes: photo.bytes,
              png: photo.png,
            );
      } catch (_) {
        if (mounted) {
          setState(() {
            _stage = null;
            _saveError = 'No se pudo subir la foto. Verifica tu conexión.';
          });
        }
        return;
      }
    }

    if (!mounted) return;
    setState(() => _stage = _Stage.saving);
    final stock = int.parse(_stock.text.trim());
    final initial = widget.initial;
    final product = Product(
      id: id,
      clinicId: clinicId,
      nombre: _nombre.text.trim(),
      categoria: _categoria!,
      descripcion: _descripcion.text.trim(),
      precio: int.parse(_precio.text.trim()),
      stock: stock,
      fotoPath: _uploadedPath ?? initial?.fotoPath ?? '',
      estado: initial == null
          ? ProductStatus.forStock(stock)
          : InventoryRules.statusAfterStock(initial.estado, stock),
    );
    try {
      if (initial == null) {
        await repo.createProduct(product);
      } else {
        await repo.updateProduct(product);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _stage = null;
          _saveError = 'No se pudo guardar el producto. Intenta de nuevo.';
        });
      }
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.success,
        content: Text(
          initial == null ? 'Producto publicado' : 'Producto actualizado',
          style: TextStyle(color: AppColors.onPrimary),
        ),
      ),
    );
    context.pop();
  }

  Future<void> _toggleActive() async {
    final product = widget.initial!;
    final deactivate = product.estado != ProductStatus.inactivo;
    if (deactivate) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Desactivar producto'),
          content: Text(
            '¿Desactivar "${product.nombre}"? Dejará de verse en la tienda. '
            'Podrás volver a publicarlo cuando quieras.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Desactivar'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    final repo = ref.read(shopRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _stage = _Stage.saving);
    try {
      if (deactivate) {
        await repo.deactivateProduct(product.clinicId, product.id);
      } else {
        await repo.reactivateProduct(product);
      }
    } catch (_) {
      if (mounted) setState(() => _stage = null);
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo cambiar el estado. Intenta de nuevo.')),
      );
      return;
    }
    messenger.showSnackBar(
      SnackBar(content: Text(deactivate ? 'Producto desactivado' : 'Producto publicado')),
    );
    if (mounted) context.pop();
  }

  /// Aviso (no bloquea) si ya hay un producto con un nombre muy parecido.
  String? _duplicateWarning() {
    final clinicId = ref.watch(currentUserProvider)?.clinicId;
    if (clinicId == null || _nombre.text.trim().length < ProductLimits.minNombre) return null;
    final inventory = ref.watch(inventoryProvider(clinicId)).value ?? const [];
    final similar =
        InventoryRules.similarProduct(_nombre.text, inventory, excludeId: widget.initial?.id);
    if (similar == null) return null;
    return 'Ya tienes un producto muy parecido: "${similar.nombre}"';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = widget.initial;
    final duplicate = _duplicateWarning();
    final enabled = !_busy;

    return Scaffold(
      appBar: AppBar(title: Text(_isNew ? 'Nuevo producto' : 'Editar producto')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ProductPhotoField(
                photoPath: initial?.fotoPath,
                bytes: _photo?.bytes,
                processing: _processingPhoto,
                enabled: enabled,
                errorText: _photoError,
                onPick: _pickPhoto,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nombre,
                enabled: enabled,
                maxLength: ProductLimits.maxNombre,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Nombre'),
                validator: ProductValidators.nombre,
                onChanged: (_) => setState(() {}),
              ),
              if (duplicate != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, size: 20, color: AppColors.slotBlocked),
                      const SizedBox(width: 8),
                      Expanded(child: Text(duplicate, style: theme.textTheme.bodySmall)),
                    ],
                  ),
                ),
              DropdownButtonFormField<ProductCategory>(
                initialValue: _categoria,
                decoration: const InputDecoration(labelText: 'Categoría'),
                isExpanded: true,
                items: [
                  for (final c in ProductCategory.values)
                    DropdownMenuItem(value: c, child: Text(c.label)),
                ],
                onChanged: enabled ? (c) => setState(() => _categoria = c) : null,
                validator: (c) => c == null ? 'Elige una categoría' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descripcion,
                enabled: enabled,
                maxLength: ProductLimits.maxDescripcion,
                minLines: 2,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Descripción (opcional)'),
                validator: ProductValidators.descripcion,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _precio,
                enabled: enabled,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Precio',
                  prefixText: '\$ ',
                  helperText: 'En pesos, sin decimales',
                ),
                validator: ProductValidators.precio,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _stock,
                enabled: enabled,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: _isNew ? 'Stock inicial' : 'Stock',
                  helperText: 'Con 0 unidades el producto queda "Agotado"',
                  helperMaxLines: 3,
                ),
                validator: ProductValidators.stock,
              ),
              const SizedBox(height: 24),
              if (_saveError != null) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline, color: theme.colorScheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _saveError!,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              if (_stage != null) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text(_stage!.label, textAlign: TextAlign.center),
                const SizedBox(height: 12),
              ],
              FilledButton(
                onPressed: _busy || _processingPhoto ? null : _save,
                child: Text(
                  _saveError != null
                      ? 'Reintentar'
                      : _isNew
                          ? 'Publicar Producto'
                          : 'Guardar cambios',
                ),
              ),
              if (initial != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _toggleActive,
                  icon: Icon(
                    initial.estado == ProductStatus.inactivo
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  label: Text(
                    initial.estado == ProductStatus.inactivo
                        ? 'Volver a publicar'
                        : 'Desactivar producto',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
