import 'package:flutter/material.dart';

import '../api/api.dart';
import 'todo_page.dart';

class LoginPage extends StatefulWidget {
  static const routeName = '/login';

  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _api = Api.instance;
  final _username = TextEditingController();
  final _password = TextEditingController();

  bool _isRegister = false;
  bool _submitting = false;
  String _error = '';

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  // 和后端 binding 标签里的约束保持一致（min=3 / min=8）。
  // 这只是为了少一次必然失败的往返，真正的校验在后端 ——
  // 前端校验是体验，不是安全边界。
  bool get _canSubmit =>
      _username.text.trim().length >= 3 &&
      _password.text.length >= 8 &&
      !_submitting;

  Future<void> _submit() async {
    if (!_canSubmit) return;

    setState(() {
      _submitting = true;
      _error = '';
    });

    try {
      final username = _username.text.trim();
      if (_isRegister) {
        await _api.register(username, _password.text);
      } else {
        await _api.login(username, _password.text);
      }

      if (!mounted) return;
      // 用 pushReplacementNamed 而不是 push：登录成功后不该还能"返回"到登录页。
      Navigator.pushReplacementNamed(context, TodoPage.routeName);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeError(e, _isRegister ? '注册失败' : '登录失败');
        _submitting = false;
      });
    }
  }

  void _toggleMode() {
    setState(() {
      _isRegister = !_isRegister;
      _error = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _isRegister ? '注册' : '登录',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _username,
                  enabled: !_submitting,
                  autofillHints: const [AutofillHints.username],
                  decoration: const InputDecoration(
                    labelText: '用户名',
                    helperText: '至少 3 个字符',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _password,
                  enabled: !_submitting,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '密码',
                    helperText: '至少 8 个字符',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _canSubmit ? _submit : null,
                  child: Text(
                    _submitting
                        ? '处理中...'
                        : (_isRegister ? '注册' : '登录'),
                  ),
                ),
                if (_error.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _submitting ? null : _toggleMode,
                  child: Text(_isRegister ? '已有账号？去登录' : '还没有账号？去注册'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
