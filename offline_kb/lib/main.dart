import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'dart:math';

void main() {
  runApp(const BeibeiApp());
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
        scaffoldBackgroundColor: const Color(0xFF0f1419),
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF5b9fd4),
          surface: const Color(0xFF161c24),
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
            category TEXT NOT NULL,
            content_hash TEXT,
            embedding_status TEXT DEFAULT 'pending',
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            updated_at TEXT DEFAULT CURRENT_TIMESTAMP
          )
        ''');
      },
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          EntriesScreen(db: _db),
          ChatScreen(db: _db),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        backgroundColor: const Color(0xFF0f1419),
        selectedItemColor: const Color(0xFF5b9fd4),
        unselectedItemColor: const Color(0xFF5c6b7f),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.folder), label: '资料'),
          BottomNavigationBarItem(icon: Icon(Icons.chat), label: '问答'),
        ],
      ),
    );
  }
}

class EntriesScreen extends StatefulWidget {
  final Database? db;
  const EntriesScreen({super.key, required this.db});

  @override
  State<EntriesScreen> createState() => _EntriesScreenState();
}

class _EntriesScreenState extends State<EntriesScreen> {
  List<Map<String, dynamic>> _entries = [];
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    if (widget.db == null) return;
    final list = await widget.db!.query('entries', orderBy: 'updated_at DESC');
    setState(() => _entries = list);
  }

  List<Map<String, dynamic>> get _filtered =>
      _filter == 'all' ? _entries : _entries.where((e) => e['category'] == _filter).toList();

  Future<void> _addEntry() async {
    final result = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(builder: (_) => const EntryFormScreen()),
    );
    if (result != null && widget.db != null) {
      await widget.db!.insert('entries', {
        ...result,
        'embedding_status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
      _loadEntries();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 48),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Text('资料', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: Color(0xFFe8eef6))),
              const Spacer(),
              Text('${_entries.length}条', style: const TextStyle(color: Color(0xFF8b9bb0))),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              _filterChip('全部', 'all'),
              _filterChip('档案', 'profile'),
              _filterChip('姨妈', 'period'),
              _filterChip('日程', 'schedule'),
              _filterChip('偏好', 'preference'),
              _filterChip('笔记', 'note'),
            ],
          ),
        ),
        Expanded(
          child: _filtered.isEmpty
              ? const Center(child: Text('还没有资料\n点右下角 + 录入', style: TextStyle(color: Color(0xFF5c6b7f)), textAlign: TextAlign.center))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _filtered.length,
                  itemBuilder: (_, i) => _entryCard(_filtered[i]),
                ),
        ),
      ],
    );
  }

  Widget _filterChip(String label, String value) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _filter = value),
        selectedColor: const Color(0xFF5b9fd4).withOpacity(0.2),
        backgroundColor: const Color(0xFF161c24),
        labelStyle: TextStyle(color: selected ? const Color(0xFF5b9fd4) : const Color(0xFF8b9bb0)),
      ),
    );
  }

  Widget _entryCard(Map<String, dynamic> entry) {
    final cat = entry['category'] as String;
    final catName = {'profile': '档案', 'period': '姨妈', 'schedule': '日程', 'preference': '偏好', 'note': '笔记'}[cat] ?? cat;
    final status = entry['embedding_status'] as String;
    final statusColor = status == 'ready' ? const Color(0xFF3dbf7a) : const Color(0xFFe0a84a);
    final statusText = status == 'ready' ? '已向量' : '向量中…';

    return Card(
      color: const Color(0xFF1a222d),
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(entry['title'] as String, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(entry['body'] as String, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF8b9bb0), fontSize: 13)),
            const SizedBox(height: 8),
            Row(children: [
              _chip(catName),
              const SizedBox(width: 6),
              _chip(statusText, color: statusColor),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, {Color color = const Color(0xFF8b9bb0)}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11)),
    );
  }
}

class EntryFormScreen extends StatefulWidget {
  const EntryFormScreen({super.key});

  @override
  State<EntryFormScreen> createState() => _EntryFormScreenState();
}

class _EntryFormScreenState extends State<EntryFormScreen> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  String _category = 'profile';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0f1419),
      appBar: AppBar(
        title: const Text('新建资料'),
        backgroundColor: const Color(0xFF0f1419),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _titleCtrl,
              decoration: InputDecoration(
                labelText: '标题',
                labelStyle: const TextStyle(color: Color(0xFF8b9bb0)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF2a3544))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF5b9fd4))),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _category,
              dropdownColor: const Color(0xFF161c24),
              decoration: InputDecoration(
                labelText: '分类',
                labelStyle: const TextStyle(color: Color(0xFF8b9bb0)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF2a3544))),
              ),
              items: const [
                DropdownMenuItem(value: 'profile', child: Text('档案')),
                DropdownMenuItem(value: 'period', child: Text('姨妈')),
                DropdownMenuItem(value: 'schedule', child: Text('日程')),
                DropdownMenuItem(value: 'preference', child: Text('偏好')),
                DropdownMenuItem(value: 'note', child: Text('笔记')),
              ],
              onChanged: (v) => setState(() => _category = v!),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TextField(
                controller: _bodyCtrl,
                maxLines: null,
                expands: true,
                decoration: InputDecoration(
                  labelText: '内容',
                  labelStyle: const TextStyle(color: Color(0xFF8b9bb0)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF2a3544))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF5b9fd4))),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () {
                  if (_titleCtrl.text.isNotEmpty && _bodyCtrl.text.isNotEmpty) {
                    Navigator.pop(context, {
                      'title': _titleCtrl.text,
                      'body': _bodyCtrl.text,
                      'category': _category,
                    });
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5b9fd4)),
                child: const Text('保存'),
              ),
            ),
          ],
        ),
      ),
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

  Future<List<Map<String, dynamic>>> _retrieve(String query) async {
    if (widget.db == null) return [];
    final entries = await widget.db!.query('entries', where: "embedding_status = 'ready'");
    if (entries.isEmpty) return [];

    // 简单关键词匹配模拟检索
    final scored = entries.map((e) {
      final text = '${e['title']} ${e['body']}'.toLowerCase();
      final chars = query.toLowerCase().split('').toSet();
      final hits = chars.where((c) => text.contains(c)).length;
      return {'entry': e, 'score': chars.isEmpty ? 0.0 : hits / chars.length};
    }).where((x) => (x['score'] as double) >= 0.25).toList()
      ..sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));

    return scored.take(3).map((x) => x['entry'] as Map<String, dynamic>).toList();
  }

  Future<void> _send() async {
    final q = _inputCtrl.text.trim();
    if (q.isEmpty || _loading) return;

    setState(() {
      _messages.add({'role': 'user', 'content': q});
      _loading = true;
      _inputCtrl.clear();
    });

    await Future.delayed(Duration(milliseconds: 600 + Random().nextInt(400)));

    final hits = await _retrieve(q);
    String answer;
    if (hits.isEmpty) {
      answer = '暂无相关个人资料';
    } else {
      answer = '根据你的资料：\n';
      for (final h in hits) {
        answer += '\n【${h['title']}】${h['body']}\n';
      }
    }

    setState(() {
      _messages.add({'role': 'bot', 'content': answer});
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 48),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Row(children: [
            Text('问答', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
            Spacer(),
            Text('只根据你的资料回答', style: TextStyle(color: Color(0xFF8b9bb0), fontSize: 12)),
          ]),
        ),
        if (_messages.isEmpty)
          Expanded(
            child: Center(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _suggestion('我身高体重多少？'),
                  _suggestion('饮食偏好'),
                  _suggestion('这周安排'),
                  _suggestion('生理期大概时间'),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (_, i) {
                final m = _messages[i];
                final isUser = m['role'] == 'user';
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
                    decoration: BoxDecoration(
                      color: isUser ? const Color(0xFF5b9fd4).withOpacity(0.15) : const Color(0xFF1a222d),
                      border: Border.all(color: isUser ? const Color(0xFF5b9fd4).withOpacity(0.3) : const Color(0xFF2a3544)),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(m['content']!, style: const TextStyle(fontSize: 14)),
                  ),
                );
              },
            ),
          ),
        if (_loading) const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(color: Color(0xFF5b9fd4))),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFF2a3544)))),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _inputCtrl,
                decoration: InputDecoration(
                  hintText: '根据我的资料回答…',
                  hintStyle: const TextStyle(color: Color(0xFF5c6b7f)),
                  filled: true,
                  fillColor: const Color(0xFF161c24),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF2a3544))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF2a3544))),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 48,
              height: 48,
              child: ElevatedButton(
                onPressed: _send,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5b9fd4), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                child: const Icon(Icons.arrow_upward, color: Colors.white),
              ),
            ),
          ]),
        ),
      ],
    );
  }

  Widget _suggestion(String text) {
    return ActionChip(
      label: Text(text, style: const TextStyle(color: Color(0xFF8b9bb0))),
      backgroundColor: Colors.transparent,
      side: const BorderSide(color: Color(0xFF2a3544), style: BorderStyle.solid),
      onPressed: () {
        _inputCtrl.text = text;
        _send();
      },
    );
  }
}
