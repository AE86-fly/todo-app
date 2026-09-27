import axios from 'axios'

// token 的存放位置抽成常量：散落各处的字面量字符串一旦拼错，
// 表现是"登录成功但下一个请求立刻 401"，很难一眼看出问题在哪。
const TOKEN_KEY = 'todo_token'
const USERNAME_KEY = 'todo_username'

// 注意：token 放在 localStorage 里，任何 XSS 都能把它读走。
// 对演示项目可以接受；要真正收紧，得改成 httpOnly + Secure 的 cookie，
// 那样 JS 读不到，代价是要额外处理 CSRF。
export const session = {
  token: () => localStorage.getItem(TOKEN_KEY),
  username: () => localStorage.getItem(USERNAME_KEY),
  save(token: string, username: string) {
    localStorage.setItem(TOKEN_KEY, token)
    localStorage.setItem(USERNAME_KEY, username)
  },
  clear() {
    localStorage.removeItem(TOKEN_KEY)
    localStorage.removeItem(USERNAME_KEY)
  },
}

// 401 的处理交给外部注册。
//
// 这里不直接 import router：http.ts 会被 router → views → stores 链式引用，
// 反向再 import router 就构成循环依赖。用一个钩子把它反转过来，
// 由 main.ts 在装配阶段接上。
let onUnauthorized: (() => void) | null = null

export function setUnauthorizedHandler(fn: () => void) {
  onUnauthorized = fn
}

const http = axios.create({
  baseURL: '/api',
  timeout: 10_000,
})

http.interceptors.request.use((config) => {
  const token = session.token()
  if (token) {
    config.headers.Authorization = `Bearer ${token}`
  }
  return config
})

http.interceptors.response.use(
  (res) => res,
  (err) => {
    if (err.response?.status === 401) {
      // 凭证失效：清掉本地状态再交给上层跳转。
      // 先清再跳，否则登录页可能拿着过期 token 又发一次请求。
      session.clear()
      onUnauthorized?.()
    }
    return Promise.reject(err)
  },
)

// 从 axios 的错误里取出后端返回的中文提示。
// 后端所有的错误响应都是 {"error": "..."} 这个形状，统一在这里解析，
// 免得每个组件各写一遍 err.response?.data?.error || '操作失败'。
export function errorMessage(err: unknown, fallback = '操作失败'): string {
  if (axios.isAxiosError(err)) {
    const msg = (err.response?.data as { error?: string } | undefined)?.error
    if (msg) return msg
    if (err.code === 'ECONNABORTED') return '请求超时'
    if (!err.response) return '无法连接到服务器'
  }
  return fallback
}

export default http
