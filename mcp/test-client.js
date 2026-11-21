#!/usr/bin/env node
/**
 * Kiểm tra nhanh MCP server mà không cần Claude Desktop: chạy server.js như Claude làm, liệt kê công cụ,
 * gọi thử whoami + báo cáo 7 ngày. Dùng: (PowerShell)
 *   $env:ERP_TOKEN="erp_..."; npm run check
 */
import { Client } from '@modelcontextprotocol/sdk/client/index.js'
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js'
import { fileURLToPath } from 'node:url'
import path from 'node:path'

const here = path.dirname(fileURLToPath(import.meta.url))
const transport = new StdioClientTransport({
  command: process.execPath,
  args: [path.join(here, 'server.js')],
  env: { ...process.env, ERP_API_URL: process.env.ERP_API_URL || 'http://localhost:5121', ERP_TOKEN: process.env.ERP_TOKEN || '' },
  stderr: 'inherit',
})
const client = new Client({ name: 'myerp-check', version: '1.0.0' })
await client.connect(transport)

const { tools } = await client.listTools()
console.log(`Có ${tools.length} công cụ: ${tools.map((t) => t.name).join(', ')}\n`)
for (const name of ['whoami', 'get_sales_report']) {
  const args = name === 'get_sales_report' ? { from: new Date(Date.now() - 6 * 864e5).toISOString().slice(0, 10), to: new Date().toISOString().slice(0, 10) } : {}
  const r = await client.callTool({ name, arguments: args })
  const text = r.content?.[0]?.text ?? ''
  console.log(`--- ${name}${r.isError ? ' (LỖI)' : ''} ---\n${text.length > 800 ? `${text.slice(0, 800)}…` : text}\n`)
}
await client.close()
