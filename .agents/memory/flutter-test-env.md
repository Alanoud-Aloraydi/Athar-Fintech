---
name: Flutter test environment quirks
description: What breaks flutter test in this repl and how to fix it
---
- The Nix-wrapped Flutter SDK reads packages from `~/.pub-cache`; if it's corrupted/partial (missing pubspec.yaml or lib files), ALL widget tests fail with VM/compile errors that look like SDK bugs. Fix: re-run `flutter pub get` (repopulates cache); no SDK patching needed.
- Widget tests for screens that build `DateFormat(..., 'ar')` must call `initializeDateFormatting('ar')` in `setUpAll` (import `package:intl/date_symbol_data_local.dart`), or they throw LocaleDataException at construction.
- `setState(() => _future = api.fetch(...))` throws "setState callback returned a Future" because the arrow closure returns the assignment value. Use a braced block for future-assigning refreshes.

**Why:** these three issues each masqueraded as "the test runner is broken"; the tests themselves were fine.
**How to apply:** when flutter tests fail en masse, check pub cache health first, then locale init, then async setState closures.
