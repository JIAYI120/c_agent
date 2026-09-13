import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'embedding_service.dart';

/// 嵌入队列服务
/// 后台串行处理 pending 状态的条目，生成向量并写入数据库
class EmbeddingQueue {
  final Database? db;
  final EmbeddingService embedding;
  bool _processing = false;
  
  EmbeddingQueue({required this.db, required this.embedding});
  
  /// 启动队列处理
  Future<void> start() async {
    if (_processing) return;
    _processing = true;
    await _processPending();
    _processing = false;
  }
  
  /// 处理所有 pending 条目
  Future<void> _processPending() async {
    if (db == null) return;
    
    final pending = await db!.query(
      'entries',
      where: "embedding_status = 'pending'",
      limit: 10,
    );
    
    for (final entry in pending) {
      await _processEntry(entry);
    }
  }
  
  /// 处理单个条目
  Future<void> _processEntry(Map<String, dynamic> entry) async {
    if (db == null) return;
    
    try {
      final body = entry['body'] as String;
      final vector = await embedding.embed(body);
      
      // 存储为逗号分隔的字符串（SQLite BLOB 转字符串兼容）
      final embeddingStr = vector.join(',');
      
      await db!.update(
        'entries',
        {
          'embedding': embeddingStr,
          'embedding_status': 'ready',
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [entry['id']],
      );
    } catch (e) {
      // 标记为失败
      await db!.update(
        'entries',
        {'embedding_status': 'failed'},
        where: 'id = ?',
        whereArgs: [entry['id']],
      );
    }
  }
}
