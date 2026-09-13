import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'dart:math';
import 'dart:ui';
import 'dart:io';
import 'package:image_picker/image_picker.dart';

// RAG 服务
import 'services/asset_unpacker.dart';
import 'services/embedding_service.dart';
import 'services/retrieval_service.dart';
import 'services/llm_service.dart';
import 'services/rag_service.dart';
import 'services/embedding_queue.dart';

// 应用常量
class AppConstants {
  static const topK = 3;
  static const threshold = 0.25;
  static const titleMaxLength = 10;
  static const bodyMaxLength = 50;
  static const pageSize = 10;
}

// 颜色常量
class AppColors {
  static const primary = Color(0xFF0a84ff);
  static const surface = Color(0xFF1c1c1e);
  static const background = Color(0xFF2c2c2e);
  static const success = Color(0xFF30d158);
  static const warning = Color(0xFFff9f0a);
  static const error = Color(0xFFff453a);
  static const purple = Color(0xFFbf5af2);
}

void main() {
  runApp(const BeibeiApp());
}

// iOS glass morphism container
class GlassContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final BorderRadius? borderRadius;

  const GlassContainer({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: borderRadius ?? BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08), width: 0.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 3, offset: const Offset(0, 1)),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius ?? BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: const Color(0xFF1c1c1e).withOpacity(0.72),
              borderRadius: borderRadius ?? BorderRadius.circular(14),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class BeibeiApp extends StatelessWidget {
  const BeibeiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '贝贝',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF0a84ff),
          surface: Color(0xFF1c1c1e),
        ),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  Database? _db;
  final _entriesRefresh = ValueNotifier<int>(0);
  bool _deleteMode = false;
  EmbeddingQueue? _embeddingQueue;

  @override
  void initState() {
    super.initState();
    _initDb();
  }

  Future<void> _initDb() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'offline_kb.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            body TEXT NOT NULL,
            category TEXT NOT NULL DEFAULT 'info',
            content_hash TEXT,
            embedding TEXT,
            embedding_status TEXT DEFAULT 'pending',
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            updated_at TEXT DEFAULT CURRENT_TIMESTAMP
          )
        ''');
      },
    );
    
    // 初始化嵌入服务并启动队列
    await _initEmbeddingQueue();
    
    setState(() {});
  }

  Future<void> _initEmbeddingQueue() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final embedding = EmbeddingService();
      await embedding.init('${appDir.path}/models/embedding.onnx');
      
      _embeddingQueue = EmbeddingQueue(db: _db, embedding: embedding);
      await _embeddingQueue!.start();
    } catch (e) {
      // 嵌入服务初始化失败，继续运行（问答功能将不可用）
      print('Embedding queue init failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['资料', '问答'];

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Large title header with FAB
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(titles[_currentIndex],
                            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: -0.02)),
                      ],
                    ),
                  ),
                  // FAB + Delete button - only show on entries tab
                  if (_currentIndex == 0)
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () async {
                            final result = await Navigator.push<Map<String, String>>(
                              context,
                              MaterialPageRoute(builder: (_) => const EntryFormScreen()),
                            );
                            if (result != null && _db != null) {
                              await _db!.insert('entries', {
                                ...result,
                                'embedding_status': 'pending',
                                'created_at': DateTime.now().toIso8601String(),
                                'updated_at': DateTime.now().toIso8601String(),
                              });
                              _entriesRefresh.value++;
                              setState(() {});
                              
                              // 启动嵌入队列
                              _embeddingQueue?.start();
                            }
                          },
                          child: Container(
                            width: 38, height: 38,
                            margin: const EdgeInsets.only(top: 6, right: 8),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF2c2c2e), Color(0xFF1c1c1e)]),
                              borderRadius: BorderRadius.circular(19),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 3, offset: const Offset(0, 1))],
                              border: Border.all(color: Colors.white.withOpacity(0.08), width: 0.5),
                            ),
                            child: const Icon(Icons.add, color: Color(0xFF0a84ff), size: 22),
                          ),
                        ),
                        // Delete mode toggle
                        GestureDetector(
                          onTap: () {
                            setState(() => _deleteMode = !_deleteMode);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(_deleteMode ? '删除模式：点击卡片删除' : '退出删除模式'), duration: const Duration(seconds: 1)),
                            );
                          },
                          child: Container(
                            width: 38, height: 38,
                            margin: const EdgeInsets.only(top: 6),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: _deleteMode
                                    ? [const Color(0xFFff453a), const Color(0xFFcc3630)]
                                    : [const Color(0xFF2c2c2e), const Color(0xFF1c1c1e)],
                              ),
                              borderRadius: BorderRadius.circular(19),
                              boxShadow: _deleteMode
                                  ? [BoxShadow(color: const Color(0xFFff453a).withOpacity(0.4), blurRadius: 6, offset: const Offset(0, 2))]
                                  : [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 3, offset: const Offset(0, 1))],
                              border: Border.all(color: Colors.white.withOpacity(0.08), width: 0.5),
                            ),
                            child: Icon(Icons.delete_outline, color: _deleteMode ? Colors.white : const Color(0xFF0a84ff), size: 20),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            // Content
            Expanded(
              child: IndexedStack(
                index: _currentIndex,
                children: [
                  EntriesScreen(
                    db: _db,
                    refreshNotifier: _entriesRefresh,
                    deleteMode: _deleteMode,
                    onDelete: (id) async {
                      await _db?.delete('entries', where: 'id = ?', whereArgs: [id]);
                      _entriesRefresh.value++;
                      setState(() {});
                    },
                  ),
                  ChatScreen(db: _db),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        margin: const EdgeInsets.fromLTRB(24, 0, 24, 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(42),
          border: Border.all(color: Colors.white.withOpacity(0.10), width: 0.5),
          color: const Color(0xFF1c1c1e).withOpacity(0.55),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 32, offset: const Offset(0, 8)),
            BoxShadow(color: Colors.black.withOpacity(0.20), blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(42),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _tabIcon(0, Icons.rectangle_rounded),
                  _tabIcon(1, Icons.chat_bubble_outline_rounded),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tabIcon(int index, IconData icon) {
    final active = _currentIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _currentIndex = index;
          if (index != 0) _deleteMode = false; // Exit delete mode when switching tabs
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF0a84ff).withOpacity(0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Icon(icon, size: 22, color: active ? const Color(0xFF0a84ff) : Colors.white.withOpacity(0.3)),
      ),
    );
  }
}

class EntriesScreen extends StatefulWidget {
  final Database? db;
  final ValueNotifier<int>? refreshNotifier;
  final bool deleteMode;
  final Function(int)? onDelete;
  const EntriesScreen({super.key, required this.db, this.refreshNotifier, this.deleteMode = false, this.onDelete});

  @override
  State<EntriesScreen> createState() => _EntriesScreenState();
}

class _EntriesScreenState extends State<EntriesScreen> {
  List<Map<String, dynamic>> _entries = [];
  String _filter = 'info';

  @override
  void initState() {
    super.initState();
    _loadEntries();
    widget.refreshNotifier?.addListener(_loadEntries);
  }

  @override
  void dispose() {
    widget.refreshNotifier?.removeListener(_loadEntries);
    super.dispose();
  }

  Future<void> _loadEntries() async {
    if (widget.db == null) return;
    final list = await widget.db!.query('entries', orderBy: 'updated_at DESC');
    setState(() => _entries = list);
  }

  List<Map<String, dynamic>> get _filtered =>
      _entries.where((e) => e['category'] == _filter).toList();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Stats
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              _statCard('${_entries.length}', '资料'),
              const SizedBox(width: 12),
              _statCard('${_entries.where((e) => e['embedding_status'] == 'ready').length}', '已向量'),
            ],
          ),
        ),
        // Filters - equal width 4 columns
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(child: _filterChip('信息', 'info')),
              const SizedBox(width: 8),
              Expanded(child: _filterChip('喜好', 'like')),
              const SizedBox(width: 8),
              Expanded(child: _filterChip('日程', 'plan')),
              const SizedBox(width: 8),
              Expanded(child: _filterChip('其它', 'other')),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // List
        Expanded(
          child: _filtered.isEmpty
              ? const Center(child: Text('还没有资料\n点标题右侧 + 开始录入',
                  style: TextStyle(color: Color(0xFFebebf54d), fontSize: 15),
                  textAlign: TextAlign.center))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _filtered.length,
                  itemBuilder: (_, i) => _entryRow(_filtered[i]),
                ),
        ),
      ],
    );
  }

  Widget _statCard(String n, String l) {
    return Expanded(
      child: GlassContainer(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(n, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: Color(0xFF0a84ff), height: 1)),
          const SizedBox(height: 4),
          Text(l, style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.3))),
        ]),
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final selected = _filter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _filter = value),
      selectedColor: const Color(0xFF0a84ff),
      backgroundColor: const Color(0xFF2c2c2e),
      labelStyle: TextStyle(
        color: selected ? Colors.white : Colors.white.withOpacity(0.6),
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }

  Widget _entryRow(Map<String, dynamic> entry) {
    final status = entry['embedding_status'] as String;
    final statusColor = status == 'ready' ? const Color(0xFF30d158) : const Color(0xFFff9f0a);
    final statusText = status == 'ready' ? '已向量' : '向量中';
    final isDeleteMode = widget.deleteMode;

    return GestureDetector(
      onTap: () async {
        if (isDeleteMode && widget.onDelete != null) {
          // Delete mode: show confirmation
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: const Color(0xFF1c1c1e),
              title: const Text('确认删除', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
              content: Text('确定删除「${entry['title']}」？', style: const TextStyle(color: Color(0xFFebebf5cc))),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消', style: TextStyle(color: Color(0xFF0a84ff))),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('删除', style: TextStyle(color: Color(0xFFff453a))),
                ),
              ],
            ),
          );
          if (confirmed == true) {
            widget.onDelete!(entry['id'] as int);
          }
        } else {
          // Normal mode: edit
          final result = await Navigator.push<Map<String, String>>(
            context,
            MaterialPageRoute(builder: (_) => EntryFormScreen(entry: entry)),
          );
          if (result != null && widget.db != null) {
            await widget.db!.update('entries', {
              ...result,
              'embedding_status': 'pending',
              'updated_at': DateTime.now().toIso8601String(),
            }, where: 'id = ?', whereArgs: [entry['id']]);
            _loadEntries();
          }
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFF38383a), width: 0.5)),
        ),
        child: Row(
          children: [
            // Body
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry['title'] as String,
                      style: const TextStyle(fontSize: 17, color: Colors.white)),
                  const SizedBox(height: 2),
                  Text(entry['body'] as String,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.3))),
                  const SizedBox(height: 6),
                  Row(children: [
                    _badge(statusText, statusColor),
                    const SizedBox(width: 6),
                    _badge(_safeSubstring(entry['updated_at'], 10), Colors.white.withOpacity(0.3)),
                  ]),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.2), size: 18),
          ],
        ),
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w500)),
    );
  }

  String _safeSubstring(dynamic value, int length) {
    if (value == null) return '';
    final str = value.toString();
    return str.length > length ? str.substring(0, length) : str;
  }
}

class EntryFormScreen extends StatefulWidget {
  final Map<String, dynamic>? entry;
  const EntryFormScreen({super.key, this.entry});

  @override
  State<EntryFormScreen> createState() => _EntryFormScreenState();
}

class _EntryFormScreenState extends State<EntryFormScreen> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _bodyCtrl;
  late String _category;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.entry?['title'] as String? ?? '');
    _bodyCtrl = TextEditingController(text: widget.entry?['body'] as String? ?? '');
    _category = widget.entry?['category'] as String? ?? 'info';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消', style: TextStyle(color: Color(0xFF0a84ff), fontSize: 16)),
        ),
        title: Text(widget.entry != null ? '编辑' : '新建资料',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        actions: [
          TextButton(
            onPressed: () {
              if (_titleCtrl.text.isNotEmpty && _bodyCtrl.text.isNotEmpty) {
                Navigator.pop(context, {
                  'title': _titleCtrl.text,
                  'body': _bodyCtrl.text,
                  'category': _category,
                });
              }
            },
            child: const Text('保存', style: TextStyle(color: Color(0xFF0a84ff), fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('标题'),
            _input(_titleCtrl, '输入标题', maxLength: 10),
            const SizedBox(height: 16),
            _label('分类'),
            _categoryPicker(),
            const SizedBox(height: 16),
            _label('内容'),
            _input(_bodyCtrl, '写下你想记住的…', maxLines: null, minLines: 6, maxLength: 50),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text.toUpperCase(),
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white.withOpacity(0.3))),
    );
  }

  Widget _input(TextEditingController ctrl, String hint, {int? maxLines, int minLines = 1, int? maxLength}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      minLines: minLines,
      maxLength: maxLength,
      style: const TextStyle(fontSize: 16, color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.2)),
        filled: true,
        fillColor: const Color(0xFF2c2c2e),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF0a84ff), width: 1),
        ),
      ),
    );
  }

  Widget _categoryPicker() {
    final cats = [
      {'key': 'info', 'name': '信息'},
      {'key': 'like', 'name': '喜好'},
      {'key': 'plan', 'name': '日程'},
      {'key': 'other', 'name': '其它'},
    ];
    return Wrap(
      spacing: 8,
      children: cats.map((c) {
        final selected = _category == c['key'];
        return ChoiceChip(
          label: Text(c['name']!),
          selected: selected,
          onSelected: (_) => setState(() => _category = c['key']!),
          selectedColor: const Color(0xFF0a84ff),
          backgroundColor: const Color(0xFF2c2c2e),
          labelStyle: TextStyle(
            color: selected ? Colors.white : Colors.white.withOpacity(0.6),
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        );
      }).toList(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final Database? db;
  const ChatScreen({super.key, required this.db});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _inputCtrl = TextEditingController();
  final List<Map<String, String>> _messages = [];
  bool _loading = false;
  RagService? _rag;
  bool _modelsReady = false;
  String? _backgroundImagePath; // 背景图片路径

  @override
  void initState() {
    super.initState();
    _initRag();
  }

  Future<void> _initRag() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      
      // 1. 解包模型
      final unpacked = await AssetUnpacker.unpackIfNeeded(appDir.path);
      if (!unpacked) {
        setState(() => _modelsReady = false);
        return;
      }
      
      // 2. 初始化 Embedding 服务（真实模型）
      final embedding = EmbeddingService();
      try {
        await embedding.init('${appDir.path}/models/embedding.onnx');
      } catch (e) {
        // Fallback 到 Mock
        print('Embedding init failed, using mock: $e');
      }
      
      // 3. 初始化 LLM 服务（真实模型）
      final llm = LlmService();
      try {
        await llm.init('${appDir.path}/models/model.gguf');
      } catch (e) {
        // Fallback 到 Mock
        print('LLM init failed, using mock: $e');
      }
      
      _rag = RagService(
        embedding: embedding,
        llm: llm,
        retrieval: RetrievalService(widget.db),
      );
      
      setState(() => _modelsReady = true);
    } catch (e) {
      setState(() => _modelsReady = false);
    }
  }

  Future<void> _send() async {
    final q = _inputCtrl.text.trim();
    if (q.isEmpty || _loading || _rag == null) return;

    setState(() {
      _messages.add({'role': 'user', 'content': q});
      _loading = true;
      _inputCtrl.clear();
    });

    try {
      final result = await _rag!.ask(q);
      setState(() {
        _messages.add({
          'role': 'bot',
          'content': result.answer,
          'refs': result.references.map((r) => r.title).join(','),
        });
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _messages.add({'role': 'bot', 'content': '回答出错：$e'});
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 背景图片
        if (_backgroundImagePath != null)
          Positioned.fill(
            child: Opacity(
              opacity: 0.15,
              child: Image.file(
                File(_backgroundImagePath!),
                fit: BoxFit.cover,
              ),
            ),
          ),
        // 主内容
        Column(
          children: [
            if (_messages.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _modelsReady ? '模型就绪，可以提问' : '正在加载模型...',
                        style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 14),
                      ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      _suggestion('我身高体重多少？'),
                      _suggestion('饮食偏好'),
                      _suggestion('这周安排'),
                      _suggestion('生理期'),
                    ],
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (_, i) {
                final m = _messages[i];
                final isUser = m['role'] == 'user';
                final refs = m['refs'] ?? '';
                
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
                    decoration: BoxDecoration(
                      color: isUser ? const Color(0xFF0a84ff) : const Color(0xFF1c1c1e),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(isUser ? 18 : 6),
                        bottomRight: Radius.circular(isUser ? 6 : 18),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m['content']!,
                            style: TextStyle(fontSize: 14, color: isUser ? Colors.white : Colors.white.withOpacity(0.9))),
                        if (!isUser && refs.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0a84ff).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('来源: $refs',
                                style: TextStyle(fontSize: 11, color: const Color(0xFF0a84ff).withOpacity(0.8))),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        if (_loading)
          Padding(
            padding: const EdgeInsets.all(8),
            child: SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: const Color(0xFF0a84ff)),
            ),
          ),
        Container(
          padding: EdgeInsets.fromLTRB(16, 10, 16, MediaQuery.of(context).padding.bottom + 10),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFF38383a), width: 0.5)),
          ),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _inputCtrl,
                style: const TextStyle(fontSize: 16, color: Colors.white),
                decoration: InputDecoration(
                  hintText: '根据我的资料回答…',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                  filled: true,
                  fillColor: const Color(0xFF1c1c1e),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _send,
              child: Container(
                width: 44, height: 44,
                decoration: const BoxDecoration(
                  color: Color(0xFF0a84ff),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_upward, color: Colors.white, size: 20),
              ),
            ),
          ],
        ), // Column
        // 设置按钮
        Positioned(
          right: 16,
          top: 8,
          child: GestureDetector(
            onTap: _showSettingsSheet,
            child: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF2c2c2e), Color(0xFF1c1c1e)]),
                borderRadius: BorderRadius.circular(19),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 3, offset: const Offset(0, 1))],
                border: Border.all(color: Colors.white.withOpacity(0.08), width: 0.5),
              ),
              child: const Icon(Icons.settings_outlined, color: Color(0xFF0a84ff), size: 20),
            ),
          ),
        ),
      ],
    );
  }

  // 背景图片设置弹窗 - 小弹窗居中
  void _showSettingsSheet() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF1c1c1e),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题栏
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('背景图片', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Color(0xFF0a84ff), size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // 选择图片按钮
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _pickImage(context),
                  icon: const Icon(Icons.upload, size: 18, color: Colors.white),
                  label: const Text('选择图片', style: TextStyle(color: Colors.white, fontSize: 14)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2c2c2e),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              if (_backgroundImagePath != null) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      setState(() => _backgroundImagePath = null);
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('背景已清除')),
                      );
                    },
                    icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFff453a)),
                    label: const Text('清除背景', style: TextStyle(color: Color(0xFFff453a), fontSize: 14)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFff453a).withOpacity(0.08),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickImage(BuildContext context) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      
      if (pickedFile != null) {
        setState(() => _backgroundImagePath = pickedFile.path);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('背景已设置')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选择图片失败: $e')),
      );
    }
  }

  Widget _suggestion(String text) {
    return ActionChip(
      label: Text(text, style: TextStyle(color: Colors.white.withOpacity(0.6))),
      backgroundColor: Colors.transparent,
      side: BorderSide(color: const Color(0xFF38383a)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      onPressed: () {
        _inputCtrl.text = text;
        _send();
      },
    );
  }
}
