<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'

import { session } from '../api/http'
import { useTodoStore } from '../stores/todo'

// 这个文件在原教程里是缺失的：router/index.ts 引用了 views/TodoView.vue，
// 但全文只给了一段"往 TodoView 里加个退出按钮"的片段，组件本体从未出现。
// 照着敲的话，构建时会直接报模块找不到。

const router = useRouter()
const store = useTodoStore()

const draft = ref('')
const username = ref(session.username() ?? '')

onMounted(() => store.load())

const remaining = computed(() => store.todos.filter((t) => !t.done).length)

async function submit() {
  const ok = await store.add(draft.value)
  // 只有真的加成功了才清空输入框。
  // 无条件清空的话，请求失败时用户刚敲的内容就没了，还得重打一遍。
  if (ok) draft.value = ''
}

async function logout() {
  session.clear()
  await router.replace({ name: 'login' })
}
</script>

<template>
  <div class="page">
    <div class="card">
      <header>
        <div>
          <h1>待办事项</h1>
          <p class="meta">
            <template v-if="store.todos.length">
              {{ remaining }} 项未完成 / 共 {{ store.todos.length }} 项
            </template>
            <template v-else>还没有待办</template>
          </p>
        </div>
        <div class="account">
          <span class="who">{{ username }}</span>
          <button class="link" @click="logout">退出</button>
        </div>
      </header>

      <form class="input-row" @submit.prevent="submit">
        <input
          v-model="draft"
          placeholder="要做点什么？"
          maxlength="255"
          :disabled="store.busy"
        />
        <button type="submit" :disabled="!draft.trim() || store.busy">添加</button>
      </form>

      <p v-if="store.error" class="error" role="alert">
        {{ store.error }}
        <button class="link" @click="store.load()">重试</button>
      </p>

      <p v-if="store.loading" class="hint">加载中...</p>

      <ul v-else-if="store.todos.length">
        <li v-for="t in store.todos" :key="t.id">
          <label>
            <input type="checkbox" :checked="t.done" @change="store.toggle(t.id)" />
            <span :class="{ done: t.done }">{{ t.title }}</span>
          </label>
          <button class="remove" title="删除" @click="store.remove(t.id)">删除</button>
        </li>
      </ul>

      <p v-else class="hint">列表是空的，在上面加一条试试。</p>
    </div>
  </div>
</template>

<style scoped>
.page {
  min-height: 100vh;
  padding: 40px 16px;
  background: #f5f6f8;
  font-family: system-ui, -apple-system, 'Segoe UI', sans-serif;
}

.card {
  max-width: 560px;
  margin: 0 auto;
  padding: 28px;
  background: #fff;
  border-radius: 10px;
  box-shadow: 0 1px 3px rgb(0 0 0 / 8%), 0 8px 24px rgb(0 0 0 / 6%);
}

header {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
  margin-bottom: 20px;
}

h1 {
  margin: 0;
  font-size: 22px;
  color: #1f2328;
}

.meta {
  margin: 4px 0 0;
  font-size: 13px;
  color: #57606a;
}

.account {
  display: flex;
  align-items: center;
  gap: 10px;
  font-size: 13px;
  color: #57606a;
  white-space: nowrap;
}

.who {
  max-width: 140px;
  overflow: hidden;
  text-overflow: ellipsis;
}

.input-row {
  display: flex;
  gap: 8px;
}

.input-row input {
  flex: 1;
  padding: 9px 11px;
  font-size: 14px;
  border: 1px solid #d0d7de;
  border-radius: 6px;
  outline: none;
}

.input-row input:focus {
  border-color: #42b883;
  box-shadow: 0 0 0 3px rgb(66 184 131 / 15%);
}

.input-row button {
  padding: 9px 18px;
  font-size: 14px;
  color: #fff;
  background: #42b883;
  border: none;
  border-radius: 6px;
  cursor: pointer;
}

.input-row button:disabled {
  background: #a8d8c2;
  cursor: not-allowed;
}

ul {
  margin: 20px 0 0;
  padding: 0;
  list-style: none;
}

li {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 10px 2px;
  border-bottom: 1px solid #eaeef2;
}

li label {
  flex: 1;
  display: flex;
  align-items: center;
  gap: 10px;
  cursor: pointer;
  min-width: 0;
}

li span {
  overflow: hidden;
  text-overflow: ellipsis;
  word-break: break-all;
  color: #1f2328;
}

.done {
  color: #8c959f;
  text-decoration: line-through;
}

.link,
.remove {
  padding: 0;
  font-size: 13px;
  background: none;
  border: none;
  cursor: pointer;
}

.link {
  color: #42b883;
}

.remove {
  color: #8c959f;
}

.remove:hover {
  color: #b42318;
}

.error {
  margin: 16px 0 0;
  padding: 8px 10px;
  font-size: 13px;
  color: #b42318;
  background: #fff1f0;
  border-radius: 6px;
}

.hint {
  margin: 20px 0 0;
  font-size: 14px;
  color: #8c959f;
}
</style>
