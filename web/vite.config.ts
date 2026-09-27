import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

export default defineConfig({
  plugins: [vue()],
  server: {
    host: '0.0.0.0',
    port: 5173,
    proxy: {
      // 开发时 /api 的转发目标。
      //
      // 用环境变量而不是写死，是因为这两种情况的目标不同：
      //   - 在容器里跑 vite dev server（compose 的 dev profile）→ http://api:8080
      //   - 在宿主机直接 npm run dev（后端 go run）→ http://localhost:8080
      // 写死其中一个，另一种就跑不起来。
      //
      // 生产环境不走这里：nginx 在同一个源上把 /api 反代给后端，
      // 前端发的是同源相对路径请求，压根不涉及跨域。
      '/api': {
        target: process.env.VITE_API_TARGET || 'http://localhost:8080',
        changeOrigin: true,
      },
    },
  },
})
