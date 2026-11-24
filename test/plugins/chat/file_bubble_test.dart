import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/attachments/attachment_status.dart';
import 'package:mascoti/core/domain/chat_message.dart';
import 'package:mascoti/core/theme/app_theme.dart';
import 'package:mascoti/plugins/chat/presentation/comun/adjuntos/file_bubble.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget bubble) => tester.pumpWidget(
        MaterialApp(theme: AppTheme.light(), home: Scaffold(body: Center(child: bubble))),
      );

  testWidgets('subiendo: barra de progreso, sin Reintentar y sin abrir', (tester) async {
    var opened = false;
    await pump(
      tester,
      FileBubble(
        nombre: 'placa.jpg',
        tipo: ChatAttachmentType.imagen,
        status: AttachmentStatus.uploading,
        onOpen: () => opened = true,
        onRetry: () {},
      ),
    );
    expect(find.text('placa.jpg'), findsOneWidget);
    expect(find.text('Subiendo…'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Reintentar'), findsNothing);
    await tester.tap(find.text('placa.jpg'));
    expect(opened, isFalse);
  });

  testWidgets('error: mensaje, Reintentar y Descartar', (tester) async {
    var retried = 0;
    var discarded = 0;
    await pump(
      tester,
      FileBubble(
        nombre: 'examen.pdf',
        tipo: ChatAttachmentType.pdf,
        status: AttachmentStatus.failed,
        error: 'Error al enviar archivo',
        onRetry: () => retried++,
        onDiscard: () => discarded++,
      ),
    );
    expect(find.text('Error al enviar archivo'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.tap(find.text('Reintentar'));
    await tester.tap(find.text('Descartar'));
    expect((retried, discarded), (1, 1));
  });

  testWidgets('listo: ícono de PDF, etiqueta del historial y se abre al tocar', (tester) async {
    var opened = false;
    await pump(
      tester,
      FileBubble(
        nombre: 'hemograma.pdf',
        tipo: ChatAttachmentType.pdf,
        status: AttachmentStatus.done,
        label: 'Del historial médico de Luna',
        onOpen: () => opened = true,
      ),
    );
    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
    expect(find.text('PDF · toca para abrir'), findsOneWidget);
    expect(find.text('Del historial médico de Luna'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.tap(find.text('hemograma.pdf'));
    expect(opened, isTrue);
  });
}
