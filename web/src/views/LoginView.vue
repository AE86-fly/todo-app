<script setup lang="ts">
import { computed, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'

import { errorMessage, session } from '../api/http'
import { authApi } from '../api/auth'

const router = useRouter()
const route = useRoute()

const username = ref('')
const password = ref('')
const isRegister = ref(false)
const submitting = ref(false)
const error = ref('')

// 和后端 binding 标签里的约束保持一致（min=3 / min=8）。
// 放这里只是为了少一次必然失败的往返，真正的校验仍然在后端 ——
// 前端校验是体验，不是安全边界。
const canSubmit = computed(
  () => username.value.trim().length >= 3 && password.value.length >= 8 && !submitting.value,
)

async function submit() {
  if (!canSubmit.value) return

  submitting.value = true
  error.value = ''
  try {
    const fn = isRegister.value ? authApi.register : authApi.login
    const data = await fn(username.value.trim(), password.value)
    session.save(data.token, data.user.username)

    // 登录前想去哪就回哪。redirect 由路由守卫写入。
    // 用 replace 而不是 push：用户不该靠"后退"回到登录页。
    const redirect = route.query.redirect
    const target = typeof redirect === 'string' && redirect.startsWith('/') ? redirect : '/'
    await router.replace(target)
  } catch (e) {
    error.value = errorMessage(e, isRegister.value ? '注册失败' : '登录失败')
  } finally {
    submitting.value = false
  }
}

function toggleMode() {
  isRegister.value = !isRegister.value
  error.value = ''
}
</script>

<template>
  <div class="page">
    <form class="card" @submit.prevent="submit">
      <h1>{{ isRegister ? '注册' : '登录' }}</h1>

      <label>
        <span>用户名</span>
        <input
          v-model="username"
          autocomplete="username"
          placeholder="至少 3 个字符"
          :disabled="submitting"
        />
      </label>

      <label>
        <span>密码</span>
        <input
          v-model="password"
          type="password"
          :autocomplete="isRegister ? 'new-password' : 'current-password'"
          placeholder="至少 8 个字符"
          :disabled="submitting"
        />
      </label>

      <button type="submit" :disabled="!canSubmit">
        {{ submitting ? '处理中...' : isRegister ? '注册' : '登录' }}
      </button>

      <p v-if="error" class="error" role="alert">{{ error }}</p>

      <p class="switch">
        {{ isRegister ? '已经有账号了？' : '还没有账号？' }}
        <a href="#" @click.prevent="toggleMode">{{ isRegister ? '去登录' : '去注册' }}</a>
      </p>
    </form>
  </div>
</template>

<style scoped>
.page {
  min-height: 100vh;
  display: grid;
  place-items: center;
  background: #f5f6f8;
  font-family: system-ui, -apple-system, 'Segoe UI', sans-serif;
}

.card {
  width: 320px;
  padding: 32px;
  background: #fff;
  border-radius: 10px;
  box-shadow: 0 1px 3px rgb(0 0 0 / 8%), 0 8px 24px rgb(0 0 0 / 6%);
  display: flex;
  flex-direction: column;
  gap: 16px;
}

h1 {
  margin: 0 0 4px;
  font-size: 22px;
  color: #1f2328;
}

label {
  display: flex;
  flex-direction: column;
  gap: 6px;
  font-size: 13px;
  color: #57606a;
}

input {
  padding: 9px 11px;
  font-size: 14px;
  border: 1px solid #d0d7de;
  border-radius: 6px;
  outline: none;
}

input:focus {
  border-color: #42b883;
  box-shadow: 0 0 0 3px rgb(66 184 131 / 15%);
}

button {
  padding: 10px;
  font-size: 15px;
  color: #fff;
  background: #42b883;
  border: none;
  border-radius: 6px;
  cursor: pointer;
}

button:disabled {
  background: #a8d8c2;
  cursor: not-allowed;
}

.error {
  margin: 0;
  padding: 8px 10px;
  font-size: 13px;
  color: #b42318;
  background: #fff1f0;
  border-radius: 6px;
}

.switch {
  margin: 0;
  font-size: 13px;
  color: #57606a;
  text-align: center;
}

.switch a {
  color: #42b883;
  text-decoration: none;
}

.switch a:hover {
  text-decoration: underline;
}
</style>
