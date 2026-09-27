import http from './http'

export interface Todo {
  id: number
  userId: number
  title: string
  done: boolean
  createdAt: string
}

export const todoApi = {
  list: () => http.get<Todo[]>('/todos').then((r) => r.data),

  create: (title: string) => http.post<Todo>('/todos', { title }).then((r) => r.data),

  toggle: (id: number) => http.patch<Todo>(`/todos/${id}/toggle`).then((r) => r.data),

  // 后端删除成功返回 204 无内容，所以不解析响应体。
  remove: (id: number) => http.delete(`/todos/${id}`).then(() => undefined),
}
