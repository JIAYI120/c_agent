import 'dart:math';

/// 检索服务
/// 使用余弦相似度在向量空间中检索相关条目
class RetrievalService {
  static const threshold = 0.25;
  
  final dynamic _db; // Database? 类型
  
  RetrievalService(this._db);
  
  /// 检索与 query 最相关的条目
  /// 返回所有 score > threshold 的条目，按分数降序
  Future<List<RetrievedEntry>> retrieve({
    required String query,
    required Future<List<double>> Function(String) embed,
  }) async {
    if (_db == null) return [];
    
    // 1. 查询所有已向量化的条目
    final entries = await _db!.query(
      'entries',
      where: "embedding_status = 'ready' AND embedding IS NOT NULL",
    );
    
    if (entries.isEmpty) return [];
    
    // 2. 计算问题向量
    final queryVec = await embed(query);
    
    // 3. 计算每个条目的相似度
    final results = <RetrievedEntry>[];
    for (final entry in entries) {
      final embedding = _parseEmbedding(entry['embedding'] as String?);
      if (embedding == null) continue;
      
      final score = _cosineSimilarity(queryVec, embedding);
      
      if (score > threshold) {
        results.add(RetrievedEntry(
          id: entry['id'] as int,
          title: entry['title'] as String,
          body: entry['body'] as String,
          score: score,
          updatedAt: entry['updated_at'] as String? ?? '',
        ));
      }
    }
    
    // 4. 按分数降序
    results.sort((a, b) => b.score.compareTo(a.score));
    return results;
  }
  
  /// 余弦相似度（向量已归一化，直接点积）
  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0;
    double dot = 0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
    }
    return dot;
  }
  
  /// 解析存储的 embedding 字符串
  /// 格式: "0.1,0.2,0.3,..." 或 BLOB 的 base64
  List<double>? _parseEmbedding(String? data) {
    if (data == null || data.isEmpty) return null;
    try {
      return data.split(',').map(double.parse).toList();
    } catch (_) {
      return null;
    }
  }
}

/// 检索结果
class RetrievedEntry {
  final int id;
  final String title;
  final String body;
  final double score;
  final String updatedAt;
  
  RetrievedEntry({
    required this.id,
    required this.title,
    required this.body,
    required this.score,
    required this.updatedAt,
  });
}
