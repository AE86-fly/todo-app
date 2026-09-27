/// <reference types="vite/client" />

// 让 TypeScript 认识 .vue 文件的默认导出。
//
// 没有这段声明，每一句 `import App from './App.vue'` 都会报
// "找不到模块 ... 或其相应的类型声明" —— 因为 TS 编译器本身不认识
// 单文件组件这种格式，需要有人告诉它"这东西导出的是一个组件"。
declare module '*.vue' {
  import type { DefineComponent } from 'vue'

  const component: DefineComponent<Record<string, unknown>, Record<string, unknown>, unknown>
  export default component
}
