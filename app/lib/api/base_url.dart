import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// 后端 API 的 base URL。
///
/// 这里刻意不用 `dart:io` 的 `Platform` —— 它在 web 平台上【整个库都不存在】，
/// 只要 import 了就是编译期错误，而不是运行时返回 false。原始教程里
/// `import 'dart:io' show Platform;` 正是这么写的，所以那份代码在 web 上
/// 连编译都过不去。
///
/// 而 foundation 里的 kIsWeb / defaultTargetPlatform 在 web、移动、桌面
/// 三个平台都能编译，一个 import 就够，不需要拆成条件导入的两个文件。
/// 构建期覆盖，用于把某个平台的产物指向别处的后端：
///
///   flutter build windows --dart-define=API_BASE_URL=http://127.0.0.1:8081/api
///
/// 为什么需要这个口子：Windows 原生 exe 连不上 WSL 里那个 8080 —— 本机实测
/// WSL2 的 localhost 转发对 8081 生效、对 8080 不生效。而 8081 上的 nginx
/// 会把 /api 反代到后端，所以 Windows 版应该指向 8081 而不是 8080。
/// 写死在下面的默认值对 Linux 桌面版是对的，对 Windows 版不对，所以留个开关。
const _override = String.fromEnvironment('API_BASE_URL');

String get apiBaseUrl {
  if (_override.isNotEmpty) return _override;

  // web 用同源相对路径。
  //
  // Flutter 产物是被 nginx 挂在 /app/ 下提供的，和 Vue 前端共用同一个源，
  // 于是 /api 会被 nginx 反代到后端 —— 同源，完全不涉及 CORS。
  //
  // 反过来写 http://localhost:8080/api 是错的，而且是双重错误：
  // 一是 api 容器根本没有对宿主机发布端口，浏览器够不着；
  // 二是就算够得着，跨源请求会先发 OPTIONS 预检，后端还得额外加 CORS 中间件。
  if (kIsWeb) return '/api';

  // Android 模拟器内部的 localhost 指的是模拟器自己，
  // 要访问宿主机得用 10.0.2.2 这个特殊地址。
  if (defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:8080/api';
  }

  // 桌面端（Windows / Linux / macOS）和 iOS 模拟器直接走本机。
  return 'http://127.0.0.1:8080/api';
}
