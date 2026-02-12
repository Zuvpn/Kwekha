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


## نصب دستور `kwekha` (اجرای سریع با یک کلمه)

بعد از اولین اجرا، داخل منو گزینه **Install/Update kwekha command** را بزنید.
از این به بعد کافیست:

```bash
sudo kwekha
```

## Update از داخل پنل

در منو گزینه **Self-update script** را بزنید. اگر دستور `kwekha` هم نصب باشد، همان هم خودکار آپدیت می‌شود.


---

## V2Ray / Xray (Recommended usage)

Kwekha برای سناریوی رایج **Iran ↔ Abroad tunnel** جهت استفاده با پنل/هسته‌های V2Ray/Xray طراحی شده:
- Forward پورت‌های رایج مثل: `80,443,2053,2083,2087,2096,8443`
- در سرور **خارج** نقش **Server** و در سرور **ایران** نقش **Client** را انتخاب کنید.
- منوی پروتکل‌ها به صورت **Basic** (کم‌حجم و مناسب موبایل) و **Advanced** (کامل) ارائه شده.

### پیشنهاد انتخاب پروتکل
برای V2Ray معمولاً این‌ها بهترین‌اند:
- `relay+wss` ★ (پیشنهادی)
- `relay+tls` ★
- `grpc` ★
- `h2` ★
- `tcp` (ساده و مناسب دیباگ)

---

## نکته مهم درباره Tunnel ID (UUID)
در gost برای `tunnel.id` یک **UUID واقعی** لازم است.  
Kwekha این UUID را **خودکار** تولید می‌کند و در جدول Summary نمایش می‌دهد تا روی سرور مقابل هم همان تنظیمات را بزنید.

---

## تست سریع تونل

### وضعیت سرویس
```bash
systemctl status gost-kwekha-<service>.service --no-pager
```

### لاگ سرویس
```bash
tail -n 80 /var/log/kwekha/<service>.log
```

### تست باز بودن پورت از بیرون (روی IP خارج)
```bash
nc -zv <ABROAD_IP> 443
curl -k https://<ABROAD_IP>:443
```

---

## Termius / Mobile terminals
در موبایل (مثل Termius) خروجی‌های خیلی بلند ممکن است سخت دیده شوند.  
به همین دلیل منوی پروتکل‌ها در حالت **Basic** کوتاه شده و گزینه **Advanced** برای نمایش لیست کامل وجود دارد.

---

## Troubleshooting

### خطا: invalid UUID length
یعنی `tunnel.id` UUID نبوده.  
Kwekha جدید این مورد را خودکار درست می‌کند. اگر سرویس قدیمی دارید، آن را حذف و دوباره Wizard را اجرا کنید:

```bash
sudo systemctl stop gost-kwekha-<service>.service
sudo systemctl disable gost-kwekha-<service>.service
sudo rm -f /etc/systemd/system/gost-kwekha-<service>.service
sudo rm -f /etc/kwekha/services/<service>.conf
sudo systemctl daemon-reload
```

### پورت اشغال است (مثل 80/443)
اگر nginx/apache روی خارج فعال باشد، gost نمی‌تواند روی همان پورت bind کند.  
با دستور زیر چک کنید:
```bash
ss -lntp | grep ':443 '
```

---

## Roadmap (short)
- Wizard پیشرفته (Advanced Mapping) با UI بهتر
- Export/Import چند سرویس با یک فایل
- اعلان تلگرام با وضعیت بهتر (latency/uptime)
