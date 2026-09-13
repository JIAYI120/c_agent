import 'package:flutter/foundation.dart';
import 'embedding_service.dart';
import 'retrieval_service.dart';
import 'llm_service.dart';

/// RAG 编排服务
/// 检索 → 构建 Prompt → 生成回答
class RagService {
  final EmbeddingService embedding;
  final LlmService llm;
  final RetrievalService retrieval;
  
  RagService({
    required this.embedding,
    required this.llm,
    required this.retrieval,
  });
  
  /// 完整 RAG 流程
  Future<RagResult> ask(String question) async {
    // 1. 检索相关资料
    final hits = await retrieval.retrieve(
      query: question,
      embed: embedding.embed,
    );
    
    if (hits.isEmpty) {
      return RagResult(
        answer: '暂无相关个人资料',
        references: [],
        hasHits: false,
      );
    }
    
    // 2. 构建 Prompt
    final prompt = buildPrompt(question, hits);
    
    // 3. 调用 LLM 生成
    final rawAnswer = await llm.generate(prompt);
    
    // 4. 解析引用标记
    final parsed = _parseReferences(rawAnswer);
    
    return RagResult(
      answer: parsed.answer,
      references: parsed.referenceIds.map((i) => hits[i - 1]).toList(),
      hasHits: true,
    );
  }
  
  /// 流式 RAG
  Stream<RagChunk> askStream(String question) async* {
    // 1. 检索
    final hits = await retrieval.retrieve(
      query: question,
      embed: embedding.embed,
    );
    
    if (hits.isEmpty) {
      yield RagChunk(text: '暂无相关个人资料', isLast: true, references: []);
      return;
    }
    
    // 2. 构建 Prompt
    final prompt = buildPrompt(question, hits);
    
    // 3. 流式生成
    final buffer = StringBuffer();
    await for (final chunk in llm.generateStream(prompt)) {
      buffer.write(chunk);
      yield RagChunk(text: chunk, isLast: false, references: []);
    }
    
    // 4. 最终解析引用
    final parsed = _parseReferences(buffer.toString());
    yield RagChunk(
      text: '',
      isLast: true,
      references: parsed.referenceIds.map((i) => hits[i - 1]).toList(),
      finalAnswer: parsed.answer,
    );
  }
  
  /// 构建 RAG Prompt
  String buildPrompt(String question, List<RetrievedEntry> hits) {
    final now = DateTime.now();
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    
    final data = hits.asMap().entries.map((entry) {
      final i = entry.key + 1;
      final h = entry.value;
      return '[资料$i] 创建时间：${h.updatedAt}\n${h.title}：${h.body}';
    }).join('\n\n');
    
    return '''你是用户的专属离线私人助手贝贝。根据下方【个人知识库】回答用户问题。

当前日期：$dateStr $timeStr

规则：
1. 只使用知识库里的信息，禁止编造
2. 如果有多条相关记录，返回最新的那条
3. 只提取问题问到的部分，不要输出整段资料
4. 如果问"这个月/上个月"，根据当前日期判断
5. 如果知识库没有相关信息，只说"暂无记录"
6. 回答末尾加上引用的资料编号，格式：|||REF:1,3|||

【个人知识库】
$data

用户问题：$question''';
  }
  
  /// 解析 |||REF:1,3||| 标记
  _ParsedAnswer _parseReferences(String raw) {
    final refMatch = RegExp(r'\|\|\|REF:([\d,]+)\|\|\|').firstMatch(raw);
    if (refMatch == null) {
      return _ParsedAnswer(answer: raw.trim(), referenceIds: []);
    }
    
    final refIds = refMatch.group(1)!.split(',').map(int.parse).toList();
    final answer = raw.replaceAll(RegExp(r'\|\|\|REF:[\d,]+\|\|\|'), '').trim();
    
    return _ParsedAnswer(answer: answer, referenceIds: refIds);
  }
}

/// RAG 结果
class RagResult {
  final String answer;
  final List<RetrievedEntry> references;
  final bool hasHits;
  
  RagResult({
    required this.answer,
    required this.references,
    required this.hasHits,
  });
}

/// RAG 流式输出块
class RagChunk {
  final String text;
  final bool isLast;
  final List<RetrievedEntry> references;
  final String? finalAnswer;
  
  RagChunk({
    required this.text,
    required this.isLast,
    required this.references,
    this.finalAnswer,
  });
}

class _ParsedAnswer {
  final String answer;
  final List<int> referenceIds;
  _ParsedAnswer({required this.answer, required this.referenceIds});
}
