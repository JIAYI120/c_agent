import 'dart:typed_data';
import 'dart:math';

/// Embedding 服务接口
/// 将文本转换为固定长度的向量（384维）
abstract class EmbeddingService {
  Future<void> init(String modelPath);
  Future<List<double>> embed(String text);
  Future<List<List<double>>> embedBatch(List<String> texts);
  void dispose();
}

/// Mock Embedding 服务（开发测试用）
/// 使用简单哈希生成伪向量，不依赖真实模型
class MockEmbeddingService implements EmbeddingService {
  @override
  Future<void> init(String modelPath) async {
    // Mock: 无需初始化
  }

  @override
  Future<List<double>> embed(String text) async {
    // 简单哈希生成 384 维向量
    final bytes = text.codeUnits;
    final vector = List<double>.filled(384, 0);
    
    for (int i = 0; i < bytes.length; i++) {
      final idx = i % 384;
      vector[idx] += bytes[i] / 255.0;
    }
    
    // L2 归一化
    final norm = sqrt(vector.fold(0.0, (sum, v) => sum + v * v));
    if (norm > 0) {
      for (int i = 0; i < vector.length; i++) {
        vector[i] /= norm;
      }
    }
    
    return vector;
  }

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    return Future.wait(texts.map(embed));
  }

  @override
  void dispose() {
    // Mock: 无需清理
  }
}

/// ONNX Runtime Embedding 服务（真实实现）
/// 需要 onnxruntime 包和预编译的 libonnxruntime.so
/// 
/// 使用方法：
/// 1. 添加依赖: onnxruntime: ^1.16.0
/// 2. 准备模型: assets/models/embedding.onnx
/// 3. 预编译库: android/app/src/main/jniLibs/arm64-v8a/libonnxruntime.so
class OnnxEmbeddingService implements EmbeddingService {
  // TODO: 实现真实 ONNX Runtime 调用
  // 需要:
  // 1. 加载 ONNX 模型
  // 2. 实现 tokenizer（或使用 sentencepiece）
  // 3. 推理并提取最后一层隐藏状态
  // 4. Mean pooling + L2 归一化
  
  @override
  Future<void> init(String modelPath) async {
    // TODO: 加载 ONNX 模型
    throw UnimplementedError('需要 ONNX Runtime 预编译库');
  }

  @override
  Future<List<double>> embed(String text) async {
    // TODO: 实现真实推理
    throw UnimplementedError('需要 ONNX Runtime 预编译库');
  }

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    return Future.wait(texts.map(embed));
  }

  @override
  void dispose() {
    // TODO: 释放 ONNX 资源
  }
}
