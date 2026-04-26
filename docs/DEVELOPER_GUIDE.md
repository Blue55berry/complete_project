# RiskGuard Developer Guide

## Architecture Overview

RiskGuard is built with Flutter and follows a layered architecture with clear separation of concerns.

### Project Structure

```
lib/
├── core/                    # Core utilities and constants
│   ├── constants/          # App constants and configurations
│   ├── services/           # Core services (method channels, etc.)
│   └── theme/              # App theming and colors
├── features/               # Feature modules
│   ├── call_detection/    # Call risk analysis
│   ├── voice_analysis/    # Voice AI detection
│   ├── message_analysis/  # Message threat detection
│   ├── video_analysis/    # Video deepfake detection
│   ├── risk_scoring/      # Overall analytics
│   └── dashboard/         # Main dashboard
└── main.dart              # App entry point
```

### Feature Module Structure

Each feature follows this structure:

```
feature_name/
├── models/               # Data models
├── providers/            # State management (Provider)
├── screens/              # UI screens
├── services/             # Business logic and API calls
└── widgets/              # Reusable widgets
```

## Key Components

### 1. Services Layer

Services contain business logic and external integrations.

**Example: VoiceAnalyzerService**
```dart
class VoiceAnalyzerService {
  // Cloud analysis
  Future<VoiceAnalysisResult> _cloudAnalysis(String filePath);
  
  // Local analysis fallback
  Future<VoiceAnalysisResult> _localAnalysis(String filePath);
  
  // Main entry point
  Future<VoiceAnalysisResult> analyzeAudio(String filePath);
}
```

**Pattern**: Try cloud analysis first, fallback to local on error.

### 2. Providers (State Management)

Using Provider for reactive state management.

**Example:**
```dart
class VideoAnalysisProvider extends ChangeNotifier {
  VideoAnalysisResult? _currentResult;
  
  Future<void> analyzeVideo(String path) async {
    _isAnalyzing = true;
    notifyListeners();
    
    final result = await _service.analyzeVideo(path);
    
    _currentResult = result;
    _isAnalyzing = false;
    notifyListeners();
  }
}
```

### 3. Screens

Screens are stateless widgets that consume providers.

**Pattern:**
```dart
class MyScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<MyProvider>(
      builder: (context, provider, _) {
        // Build UI based on provider state
      },
    );
  }
}
```

## Code Conventions

### Naming

- **Files**: `snake_case.dart`
- **Classes**: `PascalCase`
- **Variables**: `camelCase`
- **Constants**: `lowerCamelCase`
- **Private**: `_leadingUnderscore`

### Documentation

Use dartdoc comments for public APIs:

```dart
/// Analyzes a phone number for risk factors.
///
/// Returns a [CallRiskResult] with risk score, level, and explanation.
/// Throws [Exception] if analysis fails.
Future<CallRiskResult> analyzePhoneNumber(
  String phoneNumber,
  bool isIncoming,
) async { ... }
```

### Error Handling

Always handle errors gracefully:

```dart
try {
  final result = await _cloudAnalysis(path);
  return result;
} catch (e) {
  print('Cloud analysis failed: $e');
  // Fallback to local
  return await _localAnalysis(path);
}
```

## Testing

### Running Tests

```bash
# Run all tests
flutter test

# Run specific test file
flutter test test/services/voice_analyzer_service_test.dart

# Run with coverage
flutter test --coverage
```

### Test Structure

```dart
void main() {
  group('ServiceName Tests', () {
    late ServiceName service;

    setUp(() {
      service = ServiceName();
    });

    tearDown(() {
      service.dispose();
    });

    test('should do something', () async {
      // Arrange
      const input = 'test';

      // Act
      final result = await service.doSomething(input);

      // Assert
      expect(result, isNotNull);
    });
  });
}
```

### Mocking

Use mockito for mocking dependencies:

```bash
# Generate mocks
flutter packages pub run build_runner build
```

```dart
@GenerateMock([Dio])
void main() {
  late MockDio mockDio;
  
  setUp(() {
    mockDio = MockDio();
  });
}
```

## Adding New Features

### 1. Create Feature Module

```bash
mkdir -p lib/features/my_feature/{models,providers,screens,services,widgets}
```

### 2. Implement Service

```dart
// lib/features/my_feature/services/my_service.dart
class MyService {
  Future<MyResult> analyze(String input) async {
    // Implementation
  }
}
```

### 3. Create Provider

```dart
// lib/features/my_feature/providers/my_provider.dart
class MyProvider extends ChangeNotifier {
  final MyService _service = MyService();
  
  Future<void> doSomething() async {
    notifyListeners();
  }
}
```

### 4. Build UI

```dart
// lib/features/my_feature/screens/my_screen.dart
class MyScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<MyProvider>(
        builder: (context, provider, _) {
          return Text('Hello');
        },
      ),
    );
  }
}
```

### 5. Register Provider

```dart
// main.dart
MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => MyProvider()),
    // ... other providers
  ],
  child: MyApp(),
)
```

### 6. Add Tests

```dart
// test/services/my_service_test.dart
void main() {
  group('MyService Tests', () {
    test('should work', () async {
      final service = MyService();
      expect(service, isNotNull);
    });
  });
}
```

## Performance Optimization

### 1. Lazy Loading

Load data only when needed:

```dart
late final MyService _service;

void initialize() {
  _service = MyService();
}
```

### 2. Caching

Cache expensive computations:

```dart
Map<String, Result> _cache = {};

Future<Result> analyze(String input) async {
  if (_cache.containsKey(input)) {
    return _cache[input]!;
  }
  
  final result = await _expensiveComputation(input);
  _cache[input] = result;
  return result;
}
```

### 3. Debouncing

Debounce frequent operations:

```dart
Timer? _debounce;

void onSearchChanged(String query) {
  _debounce?.cancel();
  _debounce = Timer(Duration(milliseconds: 500), () {
    _performSearch(query);
  });
}
```

## CI/CD

### GitHub Actions Workflow

```yaml
name: Flutter CI

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: subosito/flutter-action@v2
      - run: flutter pub get
      - run: flutter analyze
      - run: flutter test
```

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Make changes and add tests
4. Ensure tests pass: `flutter test`
5. Commit: `git commit -m 'Add amazing feature'`
6. Push: `git push origin feature/amazing-feature`
7. Create a Pull Request

### Code Review Checklist

- [ ] Tests added/updated
- [ ] Documentation updated
- [ ] No lint errors
- [ ] Follows code conventions
- [ ] Performance considered

## Debugging

### Flutter DevTools

```bash
flutter pub global activate devtools
flutter pub global run devtools
```

### Logging

Use proper logging levels:

```dart
print('[DEBUG] Processing input...');          // Remove before production
print('[INFO] Analysis complete');
print('[WARNING] Cloud analysis failed');
print('[ERROR] Critical error: $e');
```

### Common Issues

**Issue**: Provider not updating UI
**Solution**: Ensure `notifyListeners()` is called

**Issue**: Tests failing randomly
**Solution**: Avoid using `Random()` directly, use seeded random or mocks

**Issue**: Memory leaks
**Solution**: Always dispose controllers and close streams

## Resources

- [Flutter Documentation](https://flutter.dev/docs)
- [Dart Style Guide](https://dart.dev/guides/language/effective-dart/style)
- [Provider Pattern](https://pub.dev/packages/provider)
- [Testing Best Practices](https://flutter.dev/docs/testing)

## Support

For technical questions:
- Open an issue on GitHub
- Join our Discord community
- Email: dev@riskguard.app
