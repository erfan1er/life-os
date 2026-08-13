# اعلان Push در Planer

این قابلیت یادآور را حتی وقتی Planer باز نیست ارسال می‌کند. فعال‌سازی فقط از
داخل همان دستگاه انجام می‌شود و هر دستگاه subscription جداگانه دارد.

## استفاده

1. وارد حساب Planer شوید.
2. به **تنظیمات → سیستم → اعلان‌های Push** بروید.
3. اعلان را فعال کنید و اجازهٔ مرورگر/سیستم‌عامل را تأیید کنید.
4. با «ارسال اعلان آزمایشی» دریافت اعلان را بررسی کنید.

فعلاً فقط تسک‌های باز با تاریخ و ساعت سررسید (`dueTime`) اعلان Push می‌گیرند.
زمان‌بندی با منطقهٔ زمانی `Asia/Tehran` انجام می‌شود و سرور در بازهٔ حداکثر
پنج دقیقه پس از ساعت تسک تلاش می‌کند. هر تسک با کلید پایدار dedupe می‌شود تا
با اجرای دوبارهٔ job، اعلان تکراری ارسال نشود.

## پشتیبانی دستگاه

- **iPhone/iPad:** iOS/iPadOS 16.4 یا جدیدتر، و Planer باید از Safari با
  **Add to Home Screen** نصب شده باشد. سپس اعلان را از نسخهٔ نصب‌شده فعال کنید.
- **Android و دسکتاپ:** مرورگری لازم است که Service Worker، Push API و
  Notification API را پشتیبانی کند.
- برای دریافت و ارسال Push، اینترنت لازم است. اعلان‌های درون‌برنامه‌ای محلی
  هنگام بازبودن Planer مستقل از این قابلیت هستند.

## راه‌اندازی Supabase

دو migration زیر را اجرا کنید:

```bash
supabase db push
```

- `202608130004_web_push.sql`: جدول‌های subscription و dedupe، RLS و RPCهای امن
- `202608130005_push_schedule.sql`: job زمان‌بندی هر دقیقه با `pg_cron` و `pg_net`

پیش از migration زمان‌بندی، یک مقدار تصادفی قوی را هم‌زمان در دو جای امن وارد
کنید:

1. Edge Function Secret با نام `PLANER_PUSH_CRON_SECRET`
2. Vault secret با نام `planer_push_cron_secret`

کلیدهای VAPID هم فقط باید به‌عنوان Edge Function Secret ثبت شوند:

```text
PUSH_VAPID_PUBLIC_KEY
PUSH_VAPID_PRIVATE_KEY
PUSH_VAPID_SUBJECT
```

کلید خصوصی VAPID و `PLANER_PUSH_CRON_SECRET` هرگز نباید در Git، GitHub Pages،
`index.html` یا `supabase-config.js` قرار بگیرند. کلید عمومی VAPID مجاز است در
`supabase-config.js` باشد.

سپس Functionها را منتشر کنید:

```bash
supabase functions deploy send-push-reminders --no-verify-jwt
supabase functions deploy send-push-test --no-verify-jwt
```

در migration زمان‌بندی، URL Function باید با URL پروژهٔ Supabase شما یکی باشد.
در این پروژه، job فقط با header محرمانهٔ cron Function را صدا می‌زند؛ Function
آزمایشی نیز JWT کاربر را مستقل اعتبارسنجی می‌کند و فقط subscriptionهای همان
کاربر را هدف می‌گیرد.

## حریم خصوصی

کلاینت فقط endpoint و کلیدهای عمومی subscription همان دستگاه را ثبت می‌کند.
RLS و RPC باعث می‌شوند کاربر فقط subscription خودش را ایجاد یا حذف کند. پنل
مدیر و کاربران دیگر به subscriptionها یا payload خصوصی تسک‌ها دسترسی ندارند.
