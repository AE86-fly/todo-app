import { createRouter, createWebHistory } from 'vue-router'

import { session } from '../api/http'

const router = createRouter({
  // history 模式需要服务端配合：直接访问 /login 时服务器上并没有这个文件，
  // 得靠 nginx 的 `try_files $uri $uri/ /index.html` 把请求交回给前端。
  // nginx/nginx.conf 里已经配好了，两者是配套的，改一个要记得改另一个。
  history: createWebHistory(),
  routes: [
    {
      path: '/',
      name: 'home',
      // 路由级懒加载：登录页和待办页各自打成独立的 chunk，
      // 未登录的用户不必先下载待办页的代码。
      component: () => import('../views/TodoView.vue'),
      meta: { requiresAuth: true },
    },
    {
      path: '/login',
      name: 'login',
      component: () => import('../views/LoginView.vue'),
    },
    // 兜底：任何没匹配上的路径都回首页，避免出现白屏的空白路由
    {
      path: '/:pathMatch(.*)*',
      redirect: { name: 'home' },
    },
  ],
})

router.beforeEach((to) => {
  // 只检查本地有没有 token，不校验它是否过期。
  // 过期的 token 会在第一个 API 请求上被后端拒绝（401），
  // 由 http.ts 的响应拦截器统一清掉并踢回登录页 ——
  // 在这里解析 JWT 的 exp 属于重复实现，而且客户端的时钟并不可信。
  const authed = Boolean(session.token())

  if (to.meta.requiresAuth && !authed) {
    return { name: 'login', query: { redirect: to.fullPath } }
  }
  if (to.name === 'login' && authed) {
    return { name: 'home' }
  }
})

export default router
