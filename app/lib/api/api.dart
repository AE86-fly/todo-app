import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/todo.dart';
import 'base_url.dart';

/// 凭证失效时的回调，由 main.dart 装配 —— 它需要拿到 Navigator 才能跳转。
/// 用回调而不是让这一层直接依赖 navigator：api 层不该知道任何界面的事。
typedef UnauthorizedHandler = void Function();

class Api {
  Api._() {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final prefs = await SharedPreferences.getInstance();
          final token = prefs.getString(_tokenKey);
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (err, handler) async {
          // 401 统一处理：token 过期或被拒时清掉本地凭证并踢回登录页。
          //
          // 原始教程在 Vue 端做了这件事，Flutter 端没做 ——
          // 结果是 token 过期后用户留在待办页，看到的是一个空列表，
          // 而每个请求都在后台失败，界面上没有任何提示。
          if (err.response?.statusCode == 401) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove(_tokenKey);
            onUnauthorized?.call();
          }
          handler.next(err);
        },
      ),
    );
  }

  /// 单例。所有页面共用同一个 Dio 和同一条拦截器链。
  /// 每个页面各 new 一个的话，拦截器会被重复注册，
  /// 而且实例级状态无法共享。
  static final Api instance = Api._();

  static UnauthorizedHandler? onUnauthorized;

  static const _tokenKey = 'token';

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      // 交给调用方按状态码判断，不要让 dio 对 4xx 抛异常 ——
      // 401 要走拦截器，抛出去反而不好拦。
      validateStatus: (code) => code != null && code < 400,
    ),
  );

  // ---------- 认证 ----------

  Future<void> register(String username, String password) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/auth/register',
      data: {'username': username, 'password': password},
    );
    await _saveToken(res.data!['token'] as String);
  }

  Future<void> login(String username, String password) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/auth/login',
      data: {'username': username, 'password': password},
    );
    await _saveToken(res.data!['token'] as String);
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  /// 本地有没有 token。
  ///
  /// 刻意不去解析 JWT 的 exp：客户端的时钟不可信，而且这属于重复实现 ——
  /// token 真的过期时后端会回 401，由拦截器统一处理。
  /// 这里只负责"值不值得直接进主页面"，不是一个安全判断。
  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    return token != null && token.isNotEmpty;
  }

  Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  // ---------- 待办 ----------

  Future<List<Todo>> list() async {
    final res = await _dio.get<List<dynamic>>('/todos');
    return res.data!
        .map((e) => Todo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Todo> create(String title) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/todos',
      data: {'title': title},
    );
    return Todo.fromJson(res.data!);
  }

  Future<Todo> toggle(int id) async {
    final res = await _dio.patch<Map<String, dynamic>>('/todos/$id/toggle');
    return Todo.fromJson(res.data!);
  }

  Future<void> remove(int id) => _dio.delete<void>('/todos/$id');
}

/// 把异常翻译成能直接显示给用户的中文。
///
/// 后端所有错误响应都是 {"error": "..."} 这个形状，优先用它；
/// 网络层的问题（超时、连不上）后端根本没参与，只能在这里判断。
String describeError(Object error, String fallback) {
  if (error is DioException) {
    final data = error.response?.data;
    // 写全 Map<String, dynamic> 而不是裸 Map：analysis_options.yaml 里
    // 开了 strict-raw-types，裸 Map 会被 analyzer 报出来。
    if (data is Map<String, dynamic>) {
      final msg = data['error'];
      if (msg is String) return msg;
    }
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return '请求超时，请检查网络';
      case DioExceptionType.connectionError:
        return '无法连接到服务器';
      default:
        break;
    }
  }
  return fallback;
}
