import 'dart:async';

/// LLM 服务接口
/// 加载 GGUF 模型并生成文本
abstract class LlmService {
  Future<void> init(String modelPath);
  Future<String> generate(String prompt, {
    int maxTokens = 512,
    double temperature = 0.2,
  });
  Stream<String> generateStream(String prompt, {
    int maxTokens = 512,
    double temperature = 0.2,
  });
  void dispose();
}

/// Mock LLM 服务（开发测试用）
/// 返回固定模板回答，不依赖真实模型
class MockLlmService implements LlmService {
  @override
  Future<void> init(String modelPath) async {
    // Mock: 无需初始化
  }

  @override
  Future<String> generate(String prompt, {
    int maxTokens = 512,
    double temperature = 0.2,
  }) async {
    // 模拟延迟
    await Future.delayed(const Duration(milliseconds: 300));
    
    // 从 prompt 中提取问题
    final questionMatch = RegExp(r'用户问题：(.+)').firstMatch(prompt);
    final question = questionMatch?.group(1) ?? '';
    
    // 简单关键词匹配
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
    
    // 默认回答
    return '根据你的资料回答。';
  }

  @override
  Stream<String> generateStream(String prompt, {
    int maxTokens = 512,
    double temperature = 0.2,
  }) async* {
    final answer = await generate(prompt, maxTokens: maxTokens, temperature: temperature);
    // 模拟流式输出
    for (final char in answer.split('')) {
      await Future.delayed(const Duration(milliseconds: 30));
      yield char;
    }
  }

  @override
  void dispose() {
    // Mock: 无需清理
  }
}

/// llama.cpp LLM 服务（真实实现）
/// 通过 FFI 调用 llama.cpp C 库
/// 
/// 使用方法：
/// 1. 预编译 llama.cpp: https://github.com/ggerganov/llama.cpp
/// 2. 放入库: android/app/src/main/jniLibs/arm64-v8a/libllama.so
/// 3. 准备模型: assets/models/model.gguf
class LlamaCppService implements LlmService {
  // TODO: 实现真实 llama.cpp FFI 调用
  // 需要:
  // 1. 加载 libllama.so
  // 2. llama_load_model_from_file()
  // 3. llama_new_context_with_model()
  // 4. 分词 -> 推理 -> 解码
  
  @override
  Future<void> init(String modelPath) async {
    // TODO: 加载 GGUF 模型
    throw UnimplementedError('需要 llama.cpp 预编译库');
  }

  @override
  Future<String> generate(String prompt, {
    int maxTokens = 512,
    double temperature = 0.2,
  }) async {
    // TODO: 实现真实推理
    throw UnimplementedError('需要 llama.cpp 预编译库');
  }

  @override
  Stream<String> generateStream(String prompt, {
    int maxTokens = 512,
    double temperature = 0.2,
  }) async* {
    // TODO: 实现流式推理
    throw UnimplementedError('需要 llama.cpp 预编译库');
  }

  @override
  void dispose() {
    // TODO: 释放 llama.cpp 资源
  }
}
