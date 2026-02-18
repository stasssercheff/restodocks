#!/bin/bash

# Скрипт для проверки DNS конфигурации restodocks.com

echo "================================================"
echo "🔍 Проверка DNS для restodocks.com"
echo "================================================"
echo ""

# Цвета для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Проверка A записи для apex домена
echo "1️⃣  Проверка A записи для restodocks.com..."
A_RECORD=$(dig restodocks.com +short | head -n 1)

if [ -z "$A_RECORD" ]; then
    echo -e "${RED}❌ A запись не найдена${NC}"
else
    echo -e "${GREEN}✅ A запись:${NC} $A_RECORD"
    
    # Проверка, указывает ли на Vercel (примерные IP Vercel)
    if [[ "$A_RECORD" == "76.76.21.21" ]] || [[ "$A_RECORD" =~ ^76\.76\. ]]; then
        echo -e "${GREEN}   ✅ Указывает на Vercel${NC}"
    else
        echo -e "${YELLOW}   ⚠️  Не похоже на IP Vercel (обычно 76.76.x.x)${NC}"
    fi
fi

echo ""

# Проверка CNAME для www
echo "2️⃣  Проверка CNAME для www.restodocks.com..."
WWW_CNAME=$(dig www.restodocks.com +short | head -n 1)

if [ -z "$WWW_CNAME" ]; then
    echo -e "${RED}❌ CNAME запись не найдена${NC}"
else
    echo -e "${GREEN}✅ CNAME запись:${NC} $WWW_CNAME"
    
    # Проверка, указывает ли на Vercel
    if [[ "$WWW_CNAME" == *"vercel-dns.com"* ]]; then
        echo -e "${GREEN}   ✅ Указывает на Vercel${NC}"
    else
        echo -e "${YELLOW}   ⚠️  Не указывает на Vercel${NC}"
    fi
fi

echo ""

# Проверка Nameservers
echo "3️⃣  Проверка Nameservers..."
NAMESERVERS=$(dig NS restodocks.com +short)

echo "Текущие nameservers:"
echo "$NAMESERVERS" | while read -r ns; do
    if [[ "$ns" == *"vercel-dns.com"* ]]; then
        echo -e "${GREEN}   ✅ $ns (Vercel)${NC}"
    else
        echo -e "${YELLOW}   ⚠️  $ns (не Vercel)${NC}"
    fi
done

echo ""

# Проверка SSL/HTTPS
echo "4️⃣  Проверка HTTPS..."
if curl -s -o /dev/null -w "%{http_code}" https://restodocks.com --max-time 10 | grep -q "^[23]"; then
    echo -e "${GREEN}✅ HTTPS работает${NC}"
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" https://restodocks.com --max-time 10)
    echo -e "   HTTP код: $HTTP_CODE"
else
    echo -e "${RED}❌ HTTPS не работает или сайт недоступен${NC}"
fi

echo ""

# Проверка редиректа www → apex
echo "5️⃣  Проверка редиректа www → apex..."
WWW_HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" https://www.restodocks.com --max-time 10 2>/dev/null)

if [ -n "$WWW_HTTP_CODE" ]; then
    if [[ "$WWW_HTTP_CODE" == "301" ]] || [[ "$WWW_HTTP_CODE" == "302" ]]; then
        echo -e "${GREEN}✅ Редирект настроен (код: $WWW_HTTP_CODE)${NC}"
    elif [[ "$WWW_HTTP_CODE" == "200" ]]; then
        echo -e "${YELLOW}⚠️  www работает, но редирект не настроен${NC}"
    else
        echo -e "${RED}❌ www не работает (код: $WWW_HTTP_CODE)${NC}"
    fi
else
    echo -e "${RED}❌ www.restodocks.com недоступен${NC}"
fi

echo ""
echo "================================================"
echo "📊 Резюме"
echo "================================================"

# Подсчет проблем
ISSUES=0

if [ -z "$A_RECORD" ]; then
    ((ISSUES++))
fi

if [ -z "$WWW_CNAME" ]; then
    ((ISSUES++))
fi

if ! echo "$NAMESERVERS" | grep -q "vercel-dns.com"; then
    if [[ "$A_RECORD" != "76.76.21.21" ]] && [[ ! "$A_RECORD" =~ ^76\.76\. ]]; then
        ((ISSUES++))
    fi
fi

if [ $ISSUES -eq 0 ]; then
    echo -e "${GREEN}✅ Все проверки пройдены! Домен настроен правильно.${NC}"
else
    echo -e "${YELLOW}⚠️  Найдено $ISSUES проблем(а). См. детали выше.${NC}"
    echo ""
    echo "Что делать дальше:"
    echo "1. Откройте Vercel Dashboard: https://vercel.com/dashboard"
    echo "2. Перейдите в Settings → Domains"
    echo "3. Получите точные DNS записи"
    echo "4. Обновите DNS у вашего регистратора"
    echo ""
    echo "Подробная инструкция: VERCEL_DOMAIN_CHECKLIST.md"
fi

echo ""
echo "================================================"
echo "🌐 Проверка распространения DNS по всему миру"
echo "================================================"
echo ""
echo "Онлайн инструменты для проверки:"
echo "• https://www.whatsmydns.net/#A/restodocks.com"
echo "• https://dnschecker.org/#A/restodocks.com"
echo ""
