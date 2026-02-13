# KWEKHA 🚀

Advanced Gost Tunnel Manager + Scheduler + Telegram Control Bot

------------------------------------------------------------------------

# 🇮🇷 راهنمای کامل فارسی

## معرفی

Kwekha یک ابزار حرفه‌ای مدیریت تانل Gost است که شامل:

-   راه‌انداز سریع Wizard
-   مدیریت کامل سرویس‌ها
-   Scheduler (ریست دوره‌ای تانل‌ها از 1 دقیقه تا 24 ساعت)
-   ربات تلگرام دکمه‌ای با کنترل دسترسی
-   پشتیبانی از تمامی پروتکل‌های مهم Gost

------------------------------------------------------------------------

# نصب Kwekha

## مرحله 1: دانلود و نصب CLI

``` bash
curl -fsSL https://raw.githubusercontent.com/Zuvpn/Kwekha/main/kwekha.sh -o /usr/local/bin/kwekha
chmod +x /usr/local/bin/kwekha
```

اجرای برنامه:

``` bash
kwekha
```

------------------------------------------------------------------------

# ساخت تانل (Wizard)

از منوی اصلی:

    3) Quick Setup Wizard

مراحل:

1️⃣ انتخاب نقش سرور\
- 1 = خارج (Server)\
- 2 = ایران (Client)

2️⃣ انتخاب پروتکل

3️⃣ وارد کردن پورت تانل روی خارج

4️⃣ وارد کردن IP یا دامنه خارج

5️⃣ وارد کردن پورت‌های فوروارد (مثال: 80,443)

6️⃣ انتخاب محل اجرای Xray یا سرویس مقصد

در پایان سرویس ساخته می‌شود و systemd فعال می‌شود.

------------------------------------------------------------------------

# مدیریت سرویس‌ها

از منوی CLI:

-   Start
-   Stop
-   Restart
-   Remove
-   Status
-   Logs

------------------------------------------------------------------------

# Scheduler (ریست دوره‌ای تانل)

Scheduler مستقل از تلگرام کار می‌کند.

## تنظیم بازه زمانی

از منو:

    Scheduler: Configure interval

بازه‌های قابل انتخاب: 1 دقیقه تا 24 ساعت

## فعال‌سازی

    Scheduler: Enable

## اجرای دستی

    Scheduler: Run now

لاگ‌ها:

    /var/log/kwekha/scheduler.log

------------------------------------------------------------------------

# نصب ربات تلگرام

## مرحله 1: ساخت Bot

در BotFather یک ربات بسازید و Token بگیرید.

## مرحله 2: تنظیم در CLI

از منو:

    Telegram: Setup

وارد کنید:

-   Bot Token
-   Admin IDs
-   Allowed IDs (تا 100 عدد)

## مرحله 3: اجرا

    Telegram: Start bot

------------------------------------------------------------------------

# کار با ربات تلگرام

ربات کاملاً دکمه‌ای است.

منوی اصلی شامل:

-   Services
-   Monitoring (Scheduler)
-   Config
-   Update

در تمام صفحات دکمه:

🏠 منوی اصلی

وجود دارد.

کاربران غیرمجاز پیام دریافت می‌کنند:

"شما مجاز نیستید"

------------------------------------------------------------------------

# 🇬🇧 Full English Guide

## Introduction

Kwekha is an advanced Gost tunnel manager featuring:

-   Fast setup wizard
-   Full service management
-   Force-based scheduler (1 minute to 24 hours)
-   Secure button-only Telegram bot
-   Multi-protocol support

------------------------------------------------------------------------

# Installation

## Install CLI

``` bash
curl -fsSL https://raw.githubusercontent.com/Zuvpn/Kwekha/main/kwekha.sh -o /usr/local/bin/kwekha
chmod +x /usr/local/bin/kwekha
```

Run:

``` bash
kwekha
```

------------------------------------------------------------------------

# Create Tunnel (Wizard)

Select:

    3) Quick Setup Wizard

Steps:

1.  Choose role (Server or Client)
2.  Choose protocol
3.  Enter tunnel port
4.  Enter remote IP/domain
5.  Enter forward ports (80,443)
6.  Select destination (local or remote)

Service will be created and enabled via systemd.

------------------------------------------------------------------------

# Scheduler

Force restart mode (selected configuration).

## Configure interval

1 minute to 24 hours

## Enable

Enable from CLI menu.

Logs:

    /var/log/kwekha/scheduler.log

------------------------------------------------------------------------

# Telegram Bot Setup

1.  Create bot using BotFather
2.  Setup via CLI:
    -   Enter token
    -   Enter admin IDs
    -   Enter allowed IDs
3.  Start bot service

Bot is fully button-based with:

-   Services management
-   Scheduler control
-   Always has 🏠 Home button
-   Unauthorized users receive deny message

------------------------------------------------------------------------

# Logs

Scheduler:

    /var/log/kwekha/scheduler.log

Telegram:

    /var/log/kwekha/telegram.log

Gost services:

    /var/log/kwekha/

------------------------------------------------------------------------

# Security Notes

-   Supports up to 100 allowed Telegram IDs
-   Admin role separated
-   Force restart mode for tunnel stability
-   systemd-based services

------------------------------------------------------------------------

# Author

Zuvpn
