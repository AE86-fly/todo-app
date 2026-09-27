import { createApp } from 'vue'
import { createPinia } from 'pinia'

import App from './App.vue'
import router from './router'
import { setUnauthorizedHandler } from './api/http'

const app = createApp(App)

// 把 401 的处理接到 router 上。
//
// 之所以在这里装配、而不是让 http.ts 直接 import router：http.ts 被
// router → views → stores 链式引用，反向再引用 router 就构成循环依赖。
// 代价是这层间接，换来的是依赖方向始终单向。
setUnauthorizedHandler(() => {
  const current = router.currentRoute.value
  // 已经在登录页就不要再跳一次 —— 否则登录失败（401）时会触发一次
  // 无意义的重定向，还可能把 query 里的 redirect 覆盖掉。
  if (current.name !== 'login') {
    router.push({ name: 'login', query: { redirect: current.fullPath } })
  }
})

app.use(createPinia())
app.use(router)
app.mount('#app')
