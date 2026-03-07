#!/usr/bin/env node
/**
 * Injects env vars into wrangler.jsonc before deploy.
 * Run: ADMIN_PASSWORD=x SUPABASE_URL=y SUPABASE_SERVICE_ROLE_KEY=z node scripts/inject-vars.js
 */
const fs = require('fs')
const path = require('path')

const wranglerPath = path.join(__dirname, '../wrangler.jsonc')
const content = fs.readFileSync(wranglerPath, 'utf8')

const vars = {}
if (process.env.ADMIN_PASSWORD) vars.ADMIN_PASSWORD = process.env.ADMIN_PASSWORD
if (process.env.NEXT_PUBLIC_SUPABASE_URL || process.env.SUPABASE_URL) vars.SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL || process.env.SUPABASE_URL
if (process.env.SUPABASE_SERVICE_ROLE_KEY) vars.SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY

const varsJson = JSON.stringify(vars, null, 2)
let newContent = content
if (/"vars":\s*\{/.test(content)) {
  newContent = content.replace(/"vars":\s*\{[^}]*\}/, `"vars": ${varsJson}`)
} else {
  newContent = content.replace(/"name":\s*"restodocks-admin",/, `"name": "restodocks-admin",\n  "vars": ${varsJson},`)
}
fs.writeFileSync(wranglerPath, newContent)
console.log('Injected vars:', Object.keys(vars).join(', '))
