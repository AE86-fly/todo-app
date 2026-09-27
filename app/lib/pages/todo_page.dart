import 'package:flutter/material.dart';

import '../api/api.dart';
import '../models/todo.dart';
import 'login_page.dart';

class TodoPage extends StatefulWidget {
  static const routeName = '/todos';

  const TodoPage({super.key});

  @override
  State<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends State<TodoPage> {
  final _api = Api.instance;
  final _controller = TextEditingController();

  List<Todo> _todos = [];
  bool _loading = true;
  bool _busy = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final todos = await _api.list();
      if (!mounted) return;
      setState(() => _todos = todos);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = describeError(e, '加载待办失败'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    final title = _controller.text.trim();
    if (title.isEmpty || _busy) return;

    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final created = await _api.create(title);
      if (!mounted) return;
      setState(() {
        // 插到最前面，和后端 `ORDER BY id DESC` 的顺序保持一致。
        // 放到末尾的话，新加的一条会显示在最后，而刷新之后又跑到最前 ——
        // 用户看到的是"刚加的东西自己跳了位置"。
        _todos.insert(0, created);
        // 只有真的加成功了才清空输入框：
        // 失败时清空会让用户刚敲的内容凭空消失。
        _controller.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = describeError(e, '添加失败'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggle(int id) async {
    try {
      final updated = await _api.toggle(id);
      if (!mounted) return;
      setState(() {
        final i = _todos.indexWhere((t) => t.id == id);
        if (i >= 0) _todos[i] = updated;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = describeError(e, '更新失败'));
      // 本地状态可能已经和后端不一致了，重新拉一次对齐
      await _load();
    }
  }

  Future<void> _remove(int id) async {
    try {
      await _api.remove(id);
      if (!mounted) return;
      setState(() => _todos.removeWhere((t) => t.id == id));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = describeError(e, '删除失败'));
    }
  }

  Future<void> _logout() async {
    await _api.logout();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, LoginPage.routeName, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('待办事项'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: '退出登录',
            onPressed: _logout,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: !_busy,
                    maxLength: 255,
                    decoration: const InputDecoration(
                      hintText: '要做点什么？',
                      counterText: '', // 不显示 255 字计数，占地方
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _add(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _busy ? null : _add, child: const Text('添加')),
              ],
            ),
            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _error,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                    TextButton(onPressed: _load, child: const Text('重试')),
                  ],
                ),
              ),
            Expanded(child: _buildList()),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_todos.isEmpty) {
      return const Center(child: Text('列表是空的，在上面加一条试试。'));
    }
    return ListView.builder(
      itemCount: _todos.length,
      itemBuilder: (context, i) {
        final t = _todos[i];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Checkbox(
            value: t.done,
            onChanged: (_) => _toggle(t.id),
          ),
          title: Text(
            t.title,
            style: TextStyle(
              decoration: t.done ? TextDecoration.lineThrough : null,
              color: t.done ? Theme.of(context).disabledColor : null,
            ),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '删除',
            onPressed: () => _remove(t.id),
          ),
        );
      },
    );
  }
}
