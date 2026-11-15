import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furniture_erp/components/searchable_picker.dart';

void main() {
  group('SearchableSelectFormField', () {
    test('normalizeArabic properly normalizes alef, taa marbuta, and yaa', () {
      expect(SearchableSelectFormField.normalizeArabic('إبراهيم'), 'ابراهيم');
      expect(SearchableSelectFormField.normalizeArabic('أحمد'), 'احمد');
      expect(SearchableSelectFormField.normalizeArabic('آدم'), 'ادم');
      expect(SearchableSelectFormField.normalizeArabic('فاطمة'), 'فاطمه');
      expect(SearchableSelectFormField.normalizeArabic('منى'), 'مني');
      expect(SearchableSelectFormField.normalizeArabic('طَقْمٌ'), 'طقم');
    });

    testWidgets('renders input decorator and filters items upon typing in modal sheet', (tester) async {
      int? selectedId = 1;

      final items = [
        const SearchableSelectItem<int>(value: 1, label: 'طقم كنز', subtitle: 'رصيد: 3 طقم'),
        const SearchableSelectItem<int>(value: 2, label: 'طقم ماسة', subtitle: 'رصيد: 0 طقم'),
        const SearchableSelectItem<int>(value: 3, label: 'طقم كابوتكا', subtitle: 'رصيد: 5 طقم'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: StatefulBuilder(
                builder: (ctx, setState) {
                  return SearchableSelectFormField<int>(
                    value: selectedId,
                    labelText: 'اسم الطقم (الصنف) *',
                    hintText: 'اختر الصنف',
                    items: items,
                    onChanged: (val) {
                      setState(() => selectedId = val);
                    },
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Initially displays selected label
      expect(find.text('طقم كنز'), findsOneWidget);

      // Tap to open sheet
      await tester.tap(find.text('طقم كنز'));
      await tester.pumpAndSettle();

      // Check modal sheet opened
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('طقم ماسة'), findsOneWidget);
      expect(find.text('طقم كابوتكا'), findsOneWidget);

      // Type in search field
      await tester.enterText(find.byType(TextField), 'كابوت');
      await tester.pumpAndSettle();

      // Only 'طقم كابوتكا' remains
      expect(find.text('طقم كابوتكا'), findsOneWidget);
      expect(find.text('طقم ماسة'), findsNothing);

      // Select 'طقم كابوتكا'
      await tester.tap(find.text('طقم كابوتكا'));
      await tester.pumpAndSettle();

      // Modal closed and form field updated
      expect(selectedId, 3);
      expect(find.text('طقم كابوتكا'), findsOneWidget);
    });
  });
}
