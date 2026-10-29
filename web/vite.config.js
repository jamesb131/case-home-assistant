import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  // Android Things 8.1 on the Lenovo Smart Display ships Chromium 67.
  // Keep the dashboard usable there without changing modern browser behavior.
  build: {
    target: 'chrome67',
  },
})
