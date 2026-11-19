import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:thestia/widgets/selectable_tile.dart';

void main() {
  testWidgets('SelectableTile: System (null) auswählbar', (tester) async {
    bool? selected = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SelectableTile<bool?>(
                value: null,
                groupValue: selected,
                title: 'System',
                onChanged: (v) => selected = v,
              ),
              SelectableTile<bool?>(
                value: false,
                groupValue: selected,
                title: 'Hell',
                onChanged: (v) => selected = v,
              ),
              SelectableTile<bool?>(
                value: true,
                groupValue: selected,
                title: 'Dunkel',
                onChanged: (v) => selected = v,
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();
    expect(selected, isNull, reason: 'System muss null setzen');

    await tester.tap(find.text('Dunkel'));
    await tester.pumpAndSettle();
    expect(selected, isTrue, reason: 'Dunkel muss true setzen');

    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();
    expect(selected, isNull, reason: 'System muss wieder null setzen');
  });
}
