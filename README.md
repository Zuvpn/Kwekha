# Kwekha | کویخا

**Repo:** https://github.com/Zuvpn/Kwekha

---

## فارسی (FA)

### معرفی
Kwekha یک اسکریپت مدیریتی برای **gost** است که به شما کمک می‌کند بین دو سرور (ایران/خارج) تونل بسازید، سرویس‌ها را با **systemd** مدیریت کنید، و وضعیت را با **تلگرام + کرون** مانیتور کنید.

> این پروژه ابزار مدیریت/اتوماسیون است. استفاده‌ی قانونی و مجاز بر عهده‌ی شماست.

### نصب سریع
روی هر دو سرور:

```bash
chmod +x kwekha.sh
sudo ./kwekha.sh
```

### راه‌اندازی سریع (Wizard)
از منو گزینه‌ی **Quick Setup Wizard** را بزنید.

#### روی سرور خارج (Server)
1) نقش: **1 (خارج)**
2) ترنسپورت: پیشنهاد `relay+wss`
3) پورت تونل: مثلا `8443` یا `443`
4) Tunnel ID: اگر ندارید Enter بزنید تا بسازد
5) پورت‌ها: فقط شماره پورت‌ها → مثل `80,443,2053`
6) در پایان، **Tunnel ID** را کپی کنید و ببرید روی سرور ایران

#### روی سرور ایران (Client)
1) نقش: **2 (ایران)**
2) همان ترنسپورت و پورت تونل
3) Tunnel ID: همان که از خارج گرفتید
4) پورت‌ها: `80,443,2053`
5) آی‌پی/دامنه خارج: مثلا `1.2.3.4`

> پیش‌فرض Wizard این است که هر پورت را از `127.0.0.1:PORT` فوروارد کند.  
> اگر مپینگ پیشرفته می‌خواهید، Wizard گزینه‌ی Advanced را دارد (مثل `tcp:2222->127.0.0.1:22`).

### قابلیت‌ها
- نصب gost با اسکریپت رسمی `install.sh` (آخرین نسخه)
- Wizard مرحله‌به‌مرحله برای راه‌اندازی سریع
- ساخت سرویس systemd + لاگ جداگانه برای هر سرویس
- چند سرویس هم‌زمان (هر سرویس اسم جدا)
- Health Check (وضعیت systemd + بررسی listen ports)
- تلگرام: ارسال وضعیت سرویس‌ها + آخرین خطوط لاگ
- مدیریت Cron (ارسال وضعیت هر یک ساعت)
- Export/Import کانفیگ (tar.gz)
- آپدیت خودکار خودِ اسکریپت (Self-update)
- حذف نصب کامل Kwekha (و اختیاری حذف gost)

### تلگرام
1) از منو: **Telegram setup**
2) بعد: **Enable cron** (ارسال هر یک ساعت)

### آپدیت خودکار اسکریپت
گزینه‌ی **Self-update script** نسخه جدید را از:
`https://raw.githubusercontent.com/Zuvpn/Kwekha/main/kwekha.sh`
دانلود می‌کند.  
اگر مسیر ریپو تغییر کرد، از گزینه‌ی **Set update URL** استفاده کنید.

---

## English (EN)

### Overview
Kwekha is a management script for **gost** to quickly create tunnels between two servers (Iran/Abroad), manage them as **systemd** services, and optionally report status via **Telegram + cron**.

> This is an automation/management tool. You are responsible for lawful/authorized usage.

### Quick install
On both servers:

```bash
chmod +x kwekha.sh
sudo ./kwekha.sh
```

### Quick Setup Wizard
Use **Quick Setup Wizard** from the menu.

#### On the Abroad server (Server)
1) Role: **1 (Server)**
2) Transport: recommended `relay+wss`
3) Tunnel port: e.g. `8443` or `443`
4) Tunnel ID: press Enter to auto-generate
5) Ports: just port numbers → e.g. `80,443,2053`
6) Copy the printed **Tunnel ID** and use it on the Iran server

#### On the Iran server (Client)
1) Role: **2 (Client)**
2) Same transport and tunnel port
3) Tunnel ID: paste from the server step
4) Ports: `80,443,2053`
5) Abroad IP/Domain: e.g. `1.2.3.4`

Wizard default forwards each port from `127.0.0.1:PORT`.  
Advanced port mapping is optional (e.g. `tcp:2222->127.0.0.1:22`).

### Features
- Install gost via the official `install.sh` (latest)
- Guided wizard for fast setup
- systemd services + per-service logs
- Multiple services at once
- Health Check (systemd + listening ports)
- Telegram reporting (status + last log lines)
- Cron management (hourly report)
- Export/Import config (tar.gz)
- Script self-update (pull latest from GitHub raw)
- Full uninstall (optional gost removal)

### Telegram
1) Menu: **Telegram setup**
2) Menu: **Enable cron**

### Script self-update
Uses:
`https://raw.githubusercontent.com/Zuvpn/Kwekha/main/kwekha.sh`
You can change the URL via **Set update URL**.

---
