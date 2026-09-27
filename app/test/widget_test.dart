import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:todo_app/api/base_url.dart';
import 'package:todo_app/models/todo.dart';
import 'package:todo_app/pages/login_page.dart';

void main() {
  group('Todo.fromJson', () {
    test('解析后端返回的字段', () {
      final t = Todo.fromJson(const {
        'id': 7,
        'userId': 3,
        'title': '学习 JWT',
        'done': true,
        'createdAt': '2026-09-27T05:00:00Z',
      });

      expect(t.id, 7);
      expect(t.title, '学习 JWT');
      expect(t.done, isTrue);
    });

    // 字段缺失或类型不对时必须抛，而不是默默给个默认值。
    // 静默兜底会把"后端改了字段名"变成"界面上显示空字符串"，
    // 两种故障的排查成本差得很远。
    test('字段缺失时抛出而不是静默兜底', () {
      expect(() => Todo.fromJson(const {'id': 1, 'title': 'x'}), throwsA(anything));
    });
  });

  group('apiBaseUrl', () {
    // 这个测试跑在 VM 上（不是 web），所以拿到的是桌面/移动那一支。
    // 它真正守的是"返回值非空且以 /api 结尾"这个契约 ——
    // 少写或多写斜杠都会让所有请求 404。
    test('以 /api 结尾且没有多余的斜杠', () {
      expect(apiBaseUrl, endsWith('/api'));
      expect(apiBaseUrl, isNot(endsWith('//api')));
      expect(apiBaseUrl, isNotEmpty);
    });
  });

  group('LoginPage', () {
    testWidgets('能渲染，且初始状态下提交按钮不可用', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LoginPage()));

      expect(find.text('登录'), findsWidgets);

      // 用户名和密码都空着时不该能提交 —— 否则会白发一次必然 400 的请求
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('输入满足长度要求的凭证后按钮变为可用', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LoginPage()));

      // 先只填用户名，仍然不该可用
      await tester.enterText(find.byType(TextField).first, 'alice');
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );

      // 补上足够长的密码
      await tester.enterText(find.byType(TextField).last, 'secret123');
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
    });

    testWidgets('可以切到注册模式', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LoginPage()));

      expect(find.text('还没有账号？去注册'), findsOneWidget);
      await tester.tap(find.text('还没有账号？去注册'));
      await tester.pumpAndSettle();

      expect(find.text('已有账号？去登录'), findsOneWidget);
    });
  });
}
