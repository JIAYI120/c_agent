import 'dart:math';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

/// Embedding 服务
/// 使用 ONNX Runtime 推理 MiniLM 模型
class EmbeddingService {
  OnnxRuntime? _runtime;
  OrtSession? _session;
  
  /// 初始化模型
  Future<void> init(String modelPath) async {
    _runtime = OnnxRuntime();
    _session = await _runtime!.createSession(modelPath);
  }
  
  /// 文本转向量（384维）
  Future<List<double>> embed(String text) async {
    if (_session == null) throw Exception('Embedding not initialized');
    
    // 1. 简单分词（实际应用需用 sentencepiece tokenizer）
    final tokens = _tokenize(text);
    
    // 2. 创建输入张量
    final inputTensor = await OrtValue.fromList(tokens, [1, tokens.length]);
    
    // 3. 推理
    final outputs = await _session!.run({
      'input_ids': inputTensor,
    });
    
    // 4. 提取最后一层隐藏状态并做 mean pooling
    final hidden = await outputs[0]?.asList() as List<List<List<double>>>;
    final embedding = _meanPooling(hidden, tokens.length);
    
    // 5. L2 归一化
    return _l2Normalize(embedding);
  }
  
  /// 批量向量化
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    return Future.wait(texts.map(embed));
  }
  
  /// 简单分词（实际应用需替换为 sentencepiece）
  List<int> _tokenize(String text) {
    // MiniLM 使用 BERT tokenizer
    // 简单实现：按字符转 id（实际需用真实 tokenizer）
    final chars = text.runes.toList();
    return [101] + chars.take(510).toList() + [102]; // [CLS] + tokens + [SEP]
  }
  
  /// Mean pooling
  List<double> _meanPooling(List<List<List<double>>> hidden, int seqLen) {
    final dim = hidden[0][0].length;
    final result = List<double>.filled(dim, 0);
    
    for (int i = 0; i < seqLen && i < hidden[0].length; i++) {
      for (int j = 0; j < dim; j++) {
        result[j] += hidden[0][i][j];
      }
    }
    
    for (int j = 0; j < dim; j++) {
      result[j] /= seqLen;
    }
    
    return result;
  }
  
  /// L2 归一化
  List<double> _l2Normalize(List<double> vector) {
    final norm = sqrt(vector.fold(0.0, (sum, v) => sum + v * v));
    if (norm > 0) {
      for (int i = 0; i < vector.length; i++) {
        vector[i] /= norm;
      }
    }
    return vector;
  }
  
  /// 释放资源
  void dispose() {
    _session?.close();
    // OnnxRuntime 不需要手动销毁
  }
}

/// Mock Embedding 服务（开发测试用）
class MockEmbeddingService {
  Future<void> init(String modelPath) async {}
  
  Future<List<double>> embed(String text) async {
    final bytes = text.codeUnits;
    final vector = List<double>.filled(384, 0);
    
    for (int i = 0; i < bytes.length; i++) {
      vector[i % 384] += bytes[i] / 255.0;
    }
    
    final norm = sqrt(vector.fold(0.0, (sum, v) => sum + v * v));
    if (norm > 0) {
      for (int i = 0; i < vector.length; i++) {
        vector[i] /= norm;
      }
    }
    
    return vector;
  }
  
  void dispose() {}
}
