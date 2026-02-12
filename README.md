## 🟢 نصب کامل با یک دستور (CLI + Web Panel)

```bash
sudo bash <(curl -fsSL https://raw.githubusercontent.com/Zuvpn/Kwekha/main/install.sh)
```

بعد از نصب:
- اجرای پنل ترمینال: `kwekha`
- پنل وب: `http://IP:PORT` (پورت را هنگام نصب می‌پرسد)
- بازیابی توکن: `sudo cat /etc/kwekha/web.conf | grep TOKEN=`

---

## 🟢 One-line full installer (CLI + Web Panel)

```bash
sudo bash <(curl -fsSL https://raw.githubusercontent.com/Zuvpn/Kwekha/main/install.sh)
```

After install:
- CLI: `kwekha`
- Web panel: `http://IP:PORT` (asks port during install)
- Recover token: `sudo cat /etc/kwekha/web.conf | grep TOKEN=`


---

<p align="center">
  <img src="assets/logo.svg" alt="Kwekha" width="600" />
</p>

<p align="center">
  <a href="https://github.com/Zuvpn/Kwekha/releases"><img alt="Release" src="https://img.shields.io/github/v/release/Zuvpn/Kwekha?display_name=tag"></a>
  <a href="https://github.com/Zuvpn/Kwekha/blob/main/LICENSE"><img alt="License" src="https://img.shields.io/github/license/Zuvpn/Kwekha"></a>
  <a href="https://github.com/Zuvpn/Kwekha/stargazers"><img alt="Stars" src="https://img.shields.io/github/stars/Zuvpn/Kwekha"></a>
  <a href="https://github.com/Zuvpn/Kwekha/issues"><img alt="Issues" src="https://img.shields.io/github/issues/Zuvpn/Kwekha"></a>
</p>

# Kwekha | کویخا
**Repo:** https://github.com/Zuvpn/Kwekha

Kwekha یک اسکریپت خیلی ساده برای مدیریت تونل‌های **gost** با **Wizard سریع** و سرویس‌های **systemd** است.

---

## One‑line installer (Linux)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Zuvpn/Kwekha/main/kwekha.sh)
```

سپس در منو گزینه **3) Quick Setup Wizard (FAST)** را انتخاب کنید.

---

## فارسی (FA)

### نصب
روی هر دو سرور:

```bash
chmod +x kwekha.sh
sudo ./kwekha.sh
```

یا نصب یک‌خطی (بالا).

### راه‌اندازی قدم‌به‌قدم (Wizard)
**نکته مهم:** در نسخه جدید **UUID / یوزر / پسورد حذف شده‌اند** و `tunnel.id` از **اسم سرویس** ساخته می‌شود.  
پس روی هر دو سرور، **اسم سرویس باید دقیقاً یکسان باشد**.

#### 1) روی سرور خارج (Server)
1. منو → گزینه `3`
2. Role: `1`
3. Service name: مثلا `main-tunnel`
4. Protocol: فقط عدد (پیشنهادی `relay+wss`)
5. Tunnel port: مثلا `8443` (یا `443`)
6. Ports: فقط پورت‌ها مثل `80,443,2053`

#### 2) روی سرور ایران (Client)
1. منو → گزینه `3`
2. Role: `2`
3. Service name: **همان** `main-tunnel`
4. Protocol: همان مورد خارج
5. Tunnel port: همان مورد خارج
6. Ports: همان لیست
7. Abroad IP/Domain: مثلا `1.2.3.4`

### قابلیت‌ها
- Wizard فوق سریع (فقط چند ورودی)
- نصب/آپدیت gost با installer رسمی
- ساخت سرویس‌های systemd + لاگ جدا
- چند سرویس هم‌زمان
- Health Check (systemd + listen ports)
- تلگرام: وضعیت + آخرین خطوط لاگ
- کرون: ارسال هر ۱ ساعت
- Export/Import کانفیگ
- Self-update خود اسکریپت
- Uninstall کامل Kwekha (+ اختیاری حذف gost)

### تلگرام
1) منو → `6) Telegram setup`  
2) منو → `7) Enable cron`

---

## English (EN)

### Install
On both servers:

```bash
chmod +x kwekha.sh
sudo ./kwekha.sh
```

Or use the one-liner installer above.

### Wizard setup
**Note:** UUID/username/password are removed. `tunnel.id` is derived from the **service name**.  
So both sides must use the **same service name**.

#### Abroad server (Server)
- Menu → `3`
- Role: `1`
- Service name: e.g. `main-tunnel`
- Protocol: choose by number (recommended `relay+wss`)
- Tunnel port: e.g. `8443` (or `443`)
- Ports: numbers only, e.g. `80,443,2053`

#### Iran server (Client)
- Menu → `3`
- Role: `2`
- Same service name / protocol / tunnel port / ports list
- Set Abroad IP/Domain (e.g. `1.2.3.4`)

---

## Screenshot
<p align="center">
  <img src="assets/github-screenshot.jpg" alt="GitHub screenshot" width="420" />
</p>

---

## License
MIT — see `LICENSE`.


> Wizard نکته: پروتکل‌های پیشنهادی با علامت ★ مشخص شده‌اند و بعد از وارد کردن اطلاعات، یک جدول Summary چاپ می‌شود تا عیناً روی سرور مقابل هم وارد کنید.


> Note: Protocol menu is printed to the terminal (TTY) so it always shows correctly even when the script captures the selected value internally.

## Forward مقصد (Localhost یا سرور مقابل)

در Wizard یک مرحله جدید اضافه شده:

- **روی همین سرور (127.0.0.1)**: وقتی سرویس مقصد (xray/nginx/panel) روی همان سرور اجراست.
- **روی سرور مقابل (IP/Domain)**: وقتی مثلا **پنل/Xray روی سرور خارج** است و می‌خواهید ورودی‌ها از ایران به خارج فوروارد شوند.

این گزینه جلوی خطاهای رایج مثل **Loop** و **Host Unreachable** را می‌گیرد.

## Web Panel (Go binary)

یک پنل وب حرفه‌ای (باینری تک‌فایل) داخل پوشه `webpanel/` اضافه شده.

نصب:
```bash
cd webpanel
go build -o kwekha-web .
sudo bash install_webpanel.sh
```

بازیابی Token:
```bash
sudo cat /etc/kwekha/web.conf | grep TOKEN=
sudo kwekha-web token
```

## Web Panel امکانات جدید

داخل `webpanel/` یک پنل وب حرفه‌ای (Go single-binary) اضافه شده که علاوه بر مدیریت سرویس‌ها، می‌تواند **تانل جدید بسازد** و **آمار سیستم** را نمایش دهد.

- Create Tunnel از داخل پنل (ساخت سرویس systemd + config)
- Stats: CPU / RAM / Network / Connections
- Healthcheck Timer (بدون ربات): هر ۱ تا ۶۰ دقیقه سرویس‌های `gost-kwekha-*` را بررسی و در صورت نیاز ریستارت می‌کند

**Healthcheck تنظیم از پنل:**
- Settings ➜ Health check interval

**Healthcheck از لینوکس:**
```bash
sudo kwekha healthcheck-run
```
