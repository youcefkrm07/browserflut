
import 'package:flutter/material.dart';
import 'package:flutter_app/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'fake_platform_views.dart';

void main() {
  setUp(() {
    WebViewPlatform.instance = FakeWebViewPlatform();
  });

  testWidgets('Browser screen smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const TinyBrowserApp());

    // Verify that the browser screen is rendered.
    expect(find.byType(BrowserScreen), findsOneWidget);
    expect(find.text('Tiny Browser'), findsOneWidget);
  });
}
