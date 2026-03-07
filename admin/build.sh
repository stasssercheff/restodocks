#!/usr/bin/env bash
set -e
npm ci
npx opennextjs-cloudflare build
