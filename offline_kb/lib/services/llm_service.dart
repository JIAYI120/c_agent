import 'dart:async';
import 'package:llamadart/llamadart.dart';

/// LLM 服务
/// 使用 llamadart 推理 GGUF 模型
class LlmService {
  LlamaEngine? _engine;
  ChatSession? _session;
  
  /// 初始化模型
  Future<void> init(String modelPath) async {
    _engine = LlamaEngine(LlamaBackend());
    await _engine!.loadModel(modelPath);
    _session = ChatSession(_engine!);
  }
  
  /// 生成文本
  Future<String> generate(String prompt, {
    int maxTokens = 512,
    double temperature = 0.2,
  }) async {
    if (_session == null) throw Exception('LLM not initialized');
    
    final response = StringBuffer();
    await for (final chunk in _session!.create([
      LlamaTextContent(prompt),
    ])) {
      final text = chunk.choices.first.delta.content;
      if (text != null) {
        response.write(text);
      }
    }
    
    return response.toString();
  }
  
  /// 流式生成
  Stream<String> generateStream(String prompt, {
    int maxTokens = 512,
    double temperature = 0.2,
  }) async* {
    if (_session == null) throw Exception('LLM not initialized');
    
    await for (final chunk in _session!.create([
      LlamaTextContent(prompt),
    ])) {
      final text = chunk.choices.first.delta.content;
      if (text != null) {
        yield text;
      }
    }
  }
  
  /// 释放资源
  void dispose() {
    _engine?.dispose();
  }
}

/// Mock LLM 服务（开发测试用）
class MockLlmService {
  Future<void> init(String modelPath) async {}
  
  Future<String> generate(String prompt, {
    int maxTokens = 512,
    double temperature = 0.2,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    
    final questionMatch = RegExp(r'用户问题：(.+)').firstMatch(prompt);
    final question = questionMatch?.group(1) ?? '';
    
    if (question.contains('体重') || question.contains('多重')) {
      return '根据你的记录，体重 90斤。';
    }
    if (question.contains('身高')) {
      return '身高 175cm。';
    }
    if (question.contains('吃') || question.contains('饮食')) {
      return '你不吃香菜，偏好清淡中餐，早餐常喝燕麦牛奶，对花生过敏。';
    }
    if (question.contains('安排') || question.contains('日程')) {
      return '周三 19:30 牙医复诊；周五下午产品评审；周日想整理房间。';
    }
    
    return '根据你的资料回答。';
  }
  
  Stream<String> generateStream(String prompt, {
    int maxTokens = 512,
    double temperature = 0.2,
  }) async* {
    final answer = await generate(prompt, maxTokens: maxTokens, temperature: temperature);
    for (final char in answer.split('')) {
      await Future.delayed(const Duration(milliseconds: 30));
      yield char;
    }
  }
  
  void dispose() {}
}
