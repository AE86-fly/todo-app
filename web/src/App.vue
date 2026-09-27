<script setup lang="ts">
// 根组件只是一个路由出口。
//
// 这一句是让 /login 可达的前提。原始教程在 main.ts 里装了 vue-router、
// 写了路由表，但 App.vue 的模板仍然直接渲染待办列表 —— 于是路由表
// 形同虚设：不管访问哪个路径，看到的都是待办页。加了路由却忘了把
// 根组件改成出口，是个很常见也很隐蔽的疏漏。
import { RouterView } from 'vue-router'
</script>

<template>
  <RouterView />
</template>
