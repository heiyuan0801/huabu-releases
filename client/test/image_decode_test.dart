import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:huabu_app/core/providers.dart';
import 'package:huabu_app/core/theme.dart';
import 'package:huabu_app/core/widgets.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('缩略图按布局宽度和像素密度解码，详情保留原图', (tester) async {
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetDevicePixelRatio);
    final media = MediaBytes(mimeType: 'image/png', bytes: base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a2ioAAAAASUVORK5CYII='));
    final container = ProviderContainer.test(overrides: [imageProvider('fixture').overrideWith((_) async => media)]);
    Future<void> show(double width, BoxFit fit) async {
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp(home: FTheme(data: AppTheme.dark(touch: false), child: Center(child: SizedBox(width: width, height: 100, child: ServerImage('fixture', fit: fit)))))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await show(200, BoxFit.cover);
    expect((tester.widget<Image>(find.byType(Image)).image as ResizeImage).width, 400);
    await show(120, BoxFit.cover);
    expect((tester.widget<Image>(find.byType(Image)).image as ResizeImage).width, 240);
    await show(200, BoxFit.contain);
    expect(tester.widget<Image>(find.byType(Image)).image, isA<MemoryImage>());
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
