# Kwekha Web Panel (Go single-binary)

پنل تحت وب حرفه‌ای برای مدیریت سرویس‌های ساخته‌شده توسط Kwekha (`gost-kwekha-*`):
- لیست سرویس‌ها (active/enabled)
- Start / Stop / Restart
- Status و Logs
- Login با Token (رمز ۲۵ رقمی)

## Build
```bash
cd webpanel
go build -o kwekha-web .
```

## Install
```bash
cd webpanel
sudo bash install_webpanel.sh
```

در زمان نصب، پورت پنل از شما پرسیده می‌شود و یک **Token ۲۵ رقمی** ساخته می‌شود.

## Recover token
```bash
sudo cat /etc/kwekha/web.conf | grep TOKEN=
sudo kwekha-web token
```

## Security
این پنل طبق درخواست روی `0.0.0.0:PORT` باز می‌شود.  
برای امنیت:
- با فایروال فقط IP خودت را Allow کن
- یا پشت Nginx + TLS قرار بده
