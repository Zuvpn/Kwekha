
# 🚀 Kwekha

Kwekha is a powerful tunnel management system built on top of GOST, with:

- ✅ CLI Management Panel
- ✅ Professional Web Panel
- ✅ Auto Service Creation (systemd)
- ✅ Healthcheck Timer (1–60 minutes)
- ✅ CPU / RAM / Network Stats
- ✅ One-command Full Installation

---

# 🟢 نصب کامل با یک دستور (CLI + Web Panel)

⚠️ اگر از Termius یا موبایل استفاده می‌کنید این روش را بزنید:

```bash
curl -fsSL https://raw.githubusercontent.com/Zuvpn/Kwekha/main/install.sh -o /tmp/install.sh
sudo bash /tmp/install.sh
```

در هنگام نصب:

- از شما پورت پنل پرسیده می‌شود (پیش‌فرض 8787)
- یک رمز ۲۵ رقمی به صورت خودکار ساخته می‌شود
- سرویس پنل ساخته و فعال می‌شود
- لینک ورود و توکن نمایش داده می‌شود

---

# 🌐 ورود به پنل وب

بعد از نصب:

```
http://SERVER_IP:PORT
```

مثال:

```
http://193.242.125.18:3300
```

---

# 🔐 بازیابی رمز پنل

اگر رمز را گم کردید:

```bash
sudo cat /etc/kwekha/web.conf | grep TOKEN=
```

---

# 📟 اجرای پنل ترمینالی

```bash
kwekha
```

---

# 🔁 مدیریت سرویس پنل

بررسی وضعیت:

```bash
systemctl status kwekha-web
```

ریستارت:

```bash
systemctl restart kwekha-web
```

---

# 🛠 تغییر پورت پنل

فایل تنظیمات:

```bash
sudo nano /etc/kwekha/web.conf
```

بعد:

```bash
sudo systemctl restart kwekha-web
```

---

# 📊 امکانات پنل وب

- ساخت تانل از داخل پنل
- Start / Stop / Restart سرویس‌ها
- تنظیم Healthcheck (1 تا 60 دقیقه)
- مشاهده مصرف CPU / RAM
- مشاهده ترافیک شبکه
- مشاهده تعداد کانکشن‌ها

---

# 🧠 Requirements

- Ubuntu / Debian
- Root access
- Internet access

---

# 🪪 License

MIT License
