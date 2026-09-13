import 'package:flutter/services.dart';
import 'dart:io';

/// 资产解包服务
/// 首次启动时将 APK assets 中的模型文件拷贝到应用私有目录
class AssetUnpacker {
  static const _models = {
    'assets/models/model.gguf': 'models/model.gguf',
    'assets/models/embedding.onnx': 'models/embedding.onnx',
  };

  /// 检查并解包模型文件
  /// 返回 true 表示所有模型就绪
  static Future<bool> unpackIfNeeded(String appDir) async {
    bool allReady = true;

    for (final entry in _models.entries) {
      final assetPath = entry.key;
      final targetPath = '$appDir/${entry.value}';
      final targetFile = File(targetPath);

      // 检查文件是否存在且大小合理
      if (await targetFile.exists()) {
        final size = await targetFile.length();
        if (size > 1000) continue; // 文件存在且大小合理，跳过
      }

      // 从 assets 拷贝
      try {
        final data = await rootBundle.load(assetPath);
        await targetFile.parent.create(recursive: true);
        await targetFile.writeAsBytes(data.buffer.asUint8List());
      } catch (e) {
        allReady = false;
      }
    }

    return allReady;
  }

  /// 检查模型文件是否存在
  static Future<Map<String, bool>> checkModels(String appDir) async {
    final result = <String, bool>{};
    for (final entry in _models.values) {
      final file = File('$appDir/$entry');
      result[entry] = await file.exists() && await file.length() > 1000;
    }
    return result;
  }
}
