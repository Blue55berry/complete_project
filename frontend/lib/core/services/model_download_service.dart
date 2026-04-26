import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'api_config.dart';

class ModelDownloadService extends ChangeNotifier {
  bool _isDownloading = false;
  double _progress = 0;
  String? _statusMessage;
  bool _textModelExists = false;
  bool _imageModelExists = false;

  bool get isDownloading => _isDownloading;
  double get progress => _progress;
  String? get statusMessage => _statusMessage;
  bool get textModelExists => _textModelExists;
  bool get imageModelExists => _imageModelExists;
  bool get allModelsExist => _textModelExists && _imageModelExists;

  ModelDownloadService() {
    checkModelsExist();
  }

  Future<void> checkModelsExist() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      _textModelExists = File('${dir.path}/mobilebert.tflite').existsSync();
      _imageModelExists = File('${dir.path}/mobilenet_v2.tflite').existsSync();
      notifyListeners();
    } catch (e) {
      debugPrint('ModelDownloadService: Error checking models: $e');
    }
  }

  Future<void> downloadModels() async {
    if (_isDownloading) return;

    _isDownloading = true;
    _progress = 0;
    _statusMessage = 'Initializing download...';
    notifyListeners();

    try {
      final dir = await getApplicationDocumentsDirectory();
      
      // 1. Download Text Model
      _statusMessage = 'Downloading Text AI Model (25MB)...';
      notifyListeners();
      await _downloadFile(
        '${ApiConfig.baseUrl}/static/models/mobilebert.tflite',
        '${dir.path}/mobilebert.tflite',
        (p) {
          _progress = p * 0.7; // First 70% of total progress
          notifyListeners();
        },
      );
      _textModelExists = true;

      // 2. Download Image Model
      _statusMessage = 'Downloading Image AI Model (3MB)...';
      notifyListeners();
      await _downloadFile(
        '${ApiConfig.baseUrl}/static/models/mobilenet_v2.tflite',
        '${dir.path}/mobilenet_v2.tflite',
        (p) {
          _progress = 0.7 + (p * 0.3); // Remaining 30%
          notifyListeners();
        },
      );
      _imageModelExists = true;

      _statusMessage = 'All models downloaded successfully!';
      _progress = 1.0;
    } catch (e) {
      _statusMessage = 'Download failed: $e';
      debugPrint('ModelDownloadService: $e');
    } finally {
      _isDownloading = false;
      notifyListeners();
    }
  }

  Future<void> _downloadFile(String url, String savePath, Function(double) onProgress) async {
    final response = await http.Client().send(http.Request('GET', Uri.parse(url)));
    final total = response.contentLength ?? 0;
    int received = 0;

    final file = File(savePath);
    final sink = file.openWrite();

    await response.stream.map((chunk) {
      received += chunk.length;
      if (total > 0) {
        onProgress(received / total);
      }
      return chunk;
    }).pipe(sink);

    await sink.close();
  }
}
