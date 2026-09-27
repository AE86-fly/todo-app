import 'package:flutter/material.dart';

import 'api/api.dart';
import 'pages/login_page.dart';
import 'pages/todo_page.dart';

/// 全局的 Navigator key。
///
/// 拦截器里拿到 401 时不在任何 Widget 的 build 上下文里，
/// 没有它就没法做跳转。
final navigatorKey = GlobalKey<NavigatorState>();

void main() {
  // 装配"凭证失效"的处理。
  //
  // 放在这里而不是写在 Api 内部：api 层不应该知道界面的存在。
  // pushNamedAndRemoveUntil 而不是 push：过期之后返回键不该还能
  // 退回到已经失效的页面。
  Api.onUnauthorized = () {
    navigatorKey.currentState?.pushNamedAndRemoveUntil(
      LoginPage.routeName,
      (route) => false,
    );
  };

  runApp(const TodoApp());
}

class TodoApp extends StatelessWidget {
  const TodoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '待办事项',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF42B883)),
        useMaterial3: true,
      ),
      initialRoute: _Boot.routeName,
      routes: {
        _Boot.routeName: (_) => const _Boot(),
        LoginPage.routeName: (_) => const LoginPage(),
        TodoPage.routeName: (_) => const TodoPage(),
      },
    );
  }
}

/// 启动页：判断本地有没有凭证，决定进登录页还是待办页。
///
/// 用 FutureBuilder 而不是在 main() 里 await —— main() 里同步等待
/// 会让白屏时间变长，而且 SharedPreferences 在 web 上是异步的。
class _Boot extends StatelessWidget {
  static const routeName = '/';

  const _Boot();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: Api.instance.isLoggedIn(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final target = snapshot.data! ? TodoPage.routeName : LoginPage.routeName;
        // 在 build 里直接跳转要用 post-frame 回调，
        // 否则会在同一帧内触发导航，Flutter 会报错。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            Navigator.pushReplacementNamed(context, target);
          }
        });

        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}
