import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meditrack/features/shell/nav.dart';

void main() {
  testWidgets('floating nav hugs the bottom and does not stretch over the screen', (t) async {
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 2.7;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: TabShell(
          items: const [NavItem('Overview', Icons.dashboard_outlined, Icons.dashboard_rounded), NavItem('Alerts', Icons.notifications_none_rounded, Icons.notifications_rounded)],
          pages: const [Center(child: Text('one')), Center(child: Text('two'))],
        ),
      ),
    ));
    final nav = t.getRect(find.byType(FloatingNav));
    final screen = t.view.physicalSize / t.view.devicePixelRatio;
    expect(nav.height, lessThan(120), reason: 'nav was ${nav.height}px tall');
    expect(nav.bottom, closeTo(screen.height, 1));
  });
}
