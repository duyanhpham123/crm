import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react'
import { accountApi, authApi } from '../api/authApi'
import { tokenStorage } from '../api/client'

/**
 * Trạng thái đăng nhập dùng chung cho cả ứng dụng.
 * Dùng trong component:  const { me, apps, can, login, logout } = useAuth()
 */
const AuthContext = createContext(null)

const ANONYMOUS = { status: 'anonymous', me: null, apps: [] }

export function AuthProvider({ children }) {
  // status: 'loading' | 'authenticated' | 'anonymous'
  const [session, setSession] = useState({ status: 'loading', me: null, apps: [] })

  const loadSession = useCallback(async () => {
    if (!tokenStorage.get()) {
      setSession(ANONYMOUS)
      return
    }
    try {
      const [me, apps] = await Promise.all([accountApi.me(), accountApi.apps()])
      setSession({ status: 'authenticated', me, apps })
    } catch (error) {
      if (error.response?.status === 401) tokenStorage.clear()
      setSession(ANONYMOUS)
    }
  }, [])

  useEffect(() => {
    loadSession()
    // client.js phát sự kiện này khi refresh token thất bại
    const onForcedLogout = () => setSession(ANONYMOUS)
    window.addEventListener('auth:logout', onForcedLogout)
    return () => window.removeEventListener('auth:logout', onForcedLogout)
  }, [loadSession])

  const login = useCallback(
    async (userName, password) => {
      tokenStorage.set(await authApi.login(userName, password))
      await loadSession()
    },
    [loadSession],
  )

  const logout = useCallback(async () => {
    const tokens = tokenStorage.get()
    tokenStorage.clear()
    setSession(ANONYMOUS)
    if (tokens?.refreshToken) await authApi.logout(tokens.refreshToken).catch(() => {})
  }, [])

  const value = useMemo(
    () => ({
      ...session,
      /** Kiểm tra quyền để ẩn/hiện nút. VD: can('crm.create') */
      can: (permission) => session.me?.permissions?.includes(permission) ?? false,
      login,
      logout,
    }),
    [session, login, logout],
  )

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth() {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth phải dùng bên trong <AuthProvider>')
  return ctx
}
