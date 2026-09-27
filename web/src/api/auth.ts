import http from './http'

export interface AuthResult {
  token: string
  user: {
    id: number
    username: string
    createdAt: string
  }
}

export const authApi = {
  login: (username: string, password: string) =>
    http.post<AuthResult>('/auth/login', { username, password }).then((r) => r.data),

  register: (username: string, password: string) =>
    http.post<AuthResult>('/auth/register', { username, password }).then((r) => r.data),
}
