import { defineStore } from 'pinia'
import { ref } from 'vue'

import { errorMessage } from '../api/http'
import { todoApi } from '../api/todo'
import type { Todo } from '../api/todo'

export const useTodoStore = defineStore('todo', () => {
  const todos = ref<Todo[]>([])
  const loading = ref(false)
  // 单独一个 busy 而不是复用 loading：loading 控制整页的骨架屏，
  // busy 只用来防重复提交。混用会让新增一条待办时整个列表闪一下。
  const busy = ref(false)
  const error = ref('')

  async function load() {
    loading.value = true
    error.value = ''
    try {
      todos.value = await todoApi.list()
    } catch (e) {
      error.value = errorMessage(e, '加载待办失败')
    } finally {
      loading.value = false
    }
  }

  async function add(title: string): Promise<boolean> {
    const trimmed = title.trim()
    if (!trimmed || busy.value) return false

    busy.value = true
    error.value = ''
    try {
      const created = await todoApi.create(trimmed)
      // 必须 unshift，不能 push。
      //
      // 后端按 `ORDER BY id DESC` 返回（新的在前）。如果这里 push 到末尾，
      // 新建的待办会出现在列表最下面，而刷新之后又跑到最上面 ——
      // 用户看到的现象是"刚加的东西自己跳了位置"。
      // 前端的插入位置必须和后端的排序规则一致。
      todos.value.unshift(created)
      return true
    } catch (e) {
      error.value = errorMessage(e, '添加失败')
      return false
    } finally {
      busy.value = false
    }
  }

  async function toggle(id: number) {
    error.value = ''
    try {
      const updated = await todoApi.toggle(id)
      const i = todos.value.findIndex((t) => t.id === id)
      if (i >= 0) todos.value[i] = updated
    } catch (e) {
      error.value = errorMessage(e, '更新失败')
      // 失败后重新拉一次：本地已经乐观地改过勾选状态，
      // 不重拉的话界面会显示一个后端并不认可的状态。
      await load()
    }
  }

  async function remove(id: number) {
    error.value = ''
    try {
      await todoApi.remove(id)
      todos.value = todos.value.filter((t) => t.id !== id)
    } catch (e) {
      error.value = errorMessage(e, '删除失败')
    }
  }

  return { todos, loading, busy, error, load, add, toggle, remove }
})
