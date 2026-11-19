import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    // Khi chạy dev: mọi request /api/* được chuyển sang backend .NET => không cần cấu hình CORS
    proxy: {
      '/api': 'http://localhost:5121',
    },
  },
  build: {
    // npm run build: xuất thẳng vào wwwroot của backend => deploy chỉ cần 1 server .NET
    outDir: '../backend/MyERP.Api/wwwroot',
    emptyOutDir: true,
  },
})
