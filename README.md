# Planer + Supabase

Planer همچنان یک PWA تک‌فایلی است و GitHub Pages فقط رابط را منتشر می‌کند. حساب کاربری، دعوت‌نامه و همگام‌سازی در Supabase قرار دارند. هیچ `Service Role Key`، رمز دیتابیس یا secret در `index.html`، GitHub Pages یا `supabase-config.js` قرار نمی‌گیرد.

## راه‌اندازی Supabase

1. در Supabase یک پروژه بسازید.
2. از **Project Settings → API** مقدارهای `Project URL` و `anon public key` را بردارید.
3. فایل `supabase-config.example.js` را به `supabase-config.js` کپی کنید و فقط همان دو مقدار عمومی را وارد کنید. فایل واقعی به‌علت `.gitignore` وارد Git نمی‌شود.
4. در **Authentication → Providers → Email** ورود ایمیل/رمز را فعال کنید و در **Authentication → Settings** گزینهٔ ثبت‌نام عمومی (معمولاً `Allow new users to sign up`) را خاموش کنید. این مرحله ضروری است: Edge Function با Service Role همچنان می‌تواند کاربر دعوت‌شده بسازد، اما فراخوانی مستقیم `/auth/v1/signup` با anon key دیگر حسابی ایجاد نمی‌کند.
5. در **Authentication → URL Configuration** این آدرس‌ها را در **Redirect URLs** ثبت کنید (برای هر محیطی که واقعاً استفاده می‌کنید):

   - `https://YOUR_GITHUB_USERNAME.github.io/YOUR_REPOSITORY/`
   - `http://localhost:8000/` برای توسعهٔ محلی
   - اگر مخزن به دامنهٔ سفارشی متصل است، همان URL دقیق دامنهٔ سفارشی

   `Site URL` را نیز روی URL اصلی انتشار قرار دهید. آدرس بازگشت بازیابی رمز باید دقیقاً با مقدار `redirectTo` در `supabase-config.js` یکی باشد.

## اجرای schema، RLS و RPC

فایل قابل اجرای migration در [202608120001_planer_cloud.sql](supabase/migrations/202608120001_planer_cloud.sql) است. با Supabase CLI:

```bash
supabase link --project-ref YOUR_PROJECT_REF
supabase db push
```

یا کل فایل را یک‌جا در **SQL Editor** اجرا کنید. این migration شامل موارد زیر است:

- جدول‌های `profiles`، `app_records`، `invite_codes` و `invite_redemptions`
- فعال‌سازی RLS برای همهٔ جدول‌های دارای دادهٔ کاربری
- policyهای مالکیت کاربر برای `profiles` و `app_records`
- trigger ایجاد پروفایل پیش‌فرض `user`
- RPCهای sync، دریافت رکوردها و مدیریت دعوت‌نامه
- قفل ردیفی `FOR UPDATE` در مصرف دعوت‌نامه: بررسی سقف و افزایش `used_count` در یک تراکنش انجام می‌شود.

کد دعوت خام نگهداری نمی‌شود: فقط `SHA-256` آن و یک hint کوتاه در دیتابیس ذخیره می‌شود.

## Deploy Edge Function ثبت‌نام دعوتی

```bash
supabase functions deploy register-with-invite
```

فایل آن در [index.ts](supabase/functions/register-with-invite/index.ts) است. متغیرهای `SUPABASE_URL` و `SUPABASE_SERVICE_ROLE_KEY` را runtime خود Supabase برای Edge Function فراهم می‌کند؛ service key را در فایل‌های پروژه یا GitHub Secrets مربوط به Pages قرار ندهید.

Edge Function کاربر Auth را می‌سازد، سپس RPC سرویس‌محور `consume_invite_for_user` را فراخوانی می‌کند. اگر دعوت‌نامه نامعتبر، منقضی، غیرفعال یا پر شده باشد، کاربر تازه‌ساخته‌شده حذف می‌شود. افزایش مصرف با `SELECT ... FOR UPDATE` اتمیک است و از مصرف هم‌زمان بیش از سقف جلوگیری می‌کند.

نکتهٔ عملی: این نسخه برای اینکه کاربر بتواند بلافاصله پس از دعوت وارد شود، حساب را در Edge Function با `email_confirm: true` ایجاد می‌کند. در محیط واقعی SMTP، rate limit و CAPTCHA مربوط به Auth را در داشبورد Supabase فعال و پیکربندی کنید.

## ساخت اولین admin و دعوت‌نامه

بعد از ثبت اولین کاربر دعوتی، در SQL Editor فقط همان کاربر را administrator کنید:

```sql
update public.profiles
set role = 'admin'
where id = 'UUID_OF_THE_FIRST_USER';
```

UUID را از **Authentication → Users** بردارید. سپس با همان حساب وارد Planer شوید، به **تنظیمات → حساب و همگام‌سازی** بروید و «مدیریت دعوت‌نامه‌ها» را باز کنید.

فقط کاربر `role = admin` به RPCهای دعوت‌نامه دسترسی دارد. این role به خواندن `app_records` دیگران دسترسی ندارد؛ RLS و RPCهای sync همیشه `auth.uid()` را فیلتر می‌کنند.

## رفتار Sync و انتقال داده

- Planer اول در IndexedDB محلی می‌نویسد؛ اینترنت برای ثبت تسک یا داده‌های دیگر لازم نیست.
- پس از انتقال داده‌های دستگاه به حساب، تغییرات در `syncQueue` محلی قرار می‌گیرند و هنگام آنلاین‌شدن ارسال می‌شوند.
- دستگاه جدیدی که دادهٔ محلی ندارد، پس از ورود داده‌های کاربر را دریافت می‌کند.
- کاربر دارای دادهٔ قدیمی ابتدا در تنظیمات تعداد رکوردها را می‌بیند و با انتخاب آگاهانهٔ «انتقال داده‌های این دستگاه به حساب» یک backup محلی pinned می‌گیرد؛ انتقال تکراری از شناسهٔ پایدار هر رکورد استفاده می‌کند و دادهٔ تکراری نمی‌سازد.
- حذف‌ها soft delete هستند: tombstone با `deletedAt` در ابر می‌ماند تا حذف در همهٔ دستگاه‌ها منتقل شود.
- status بالای برنامه و تنظیمات نشان می‌دهد: آفلاین، در حال همگام‌سازی، خطا، انتقال لازم، یا همگام؛ آخرین زمان همگام‌سازی هم در تنظیمات دیده می‌شود.

### حل تداخل

هر رکورد `client_updated_at` و `version` دارد. در sync معمول، تغییر با زمان محلی جدیدتر برنده است؛ اگر زمان برابر باشد، نسخهٔ بزرگ‌تر برنده است. این **Last Valid Write Wins** است. چون دو دستگاه بدون ساعت دقیق ممکن است دادهٔ هم‌زمان را overwrite کنند، Planer برای ویرایش هم‌زمان یک فیلد یک سیستم merge معنایی ندارد. رکوردهای حذف‌شده نیز همان قاعده را دنبال می‌کنند.

Realtime عمداً در این نسخه فعال نشده است: pull هنگام ورود، آنلاین‌شدن، فوکوس و ارسال تغییرات انجام می‌شود و مسیر RLS ساده و قابل‌ممیزی می‌ماند. برای اعلان آنی بین دستگاه‌ها می‌توان بعداً Realtime را فقط برای `app_records` و با همان RLS افزود؛ نباید قبل از تست فشار و بازبینی مصرف اتصال فعال شود.

## انتشار در GitHub Pages

1. فایل‌های پروژه، از جمله `index.html`، `sw.js`، migration و README را commit/push کنید. `supabase-config.js` را commit نکنید.
2. در GitHub Pages، branch و پوشهٔ ریشهٔ انتشار را انتخاب کنید.
3. برای محیط Pages، `supabase-config.js` واقعی باید کنار `index.html` روی همان origin deploy شود. چون فایل ignored است، آن را در روند deployment به‌صورت secret/build artifact تولید کنید؛ اگر workflow ندارید، باید آن را به‌صورت کنترل‌شده در میزبان قرار دهید.
4. هر بار که `index.html` تغییر می‌کند، نسخهٔ `CACHE` در `sw.js` را افزایش دهید تا PWA نصب‌شده نسخهٔ تازه را دریافت کند.

## محدودیت‌ها و نکات امنیتی

- `anon key` عمومی است؛ حفاظت واقعی با RLS و RPCهای `security definer` همراه با چک `auth.uid()`/admin انجام می‌شود.
- Service role فقط داخل Edge Function است.
- raw invite code فقط هنگام ساخت در UI دیده می‌شود؛ پس از بستن پنل قابل بازیابی نیست.
- Export و backup محلیِ فعلی حفظ شده‌اند؛ export رمزهای PIN و کلید AI را مثل قبل redact می‌کند. PIN، پاسخ بازیابی PIN، کلید AI، اعلان مرورگر و وضعیت‌های صرفاً دستگاهی عمداً sync نمی‌شوند.
- session ورود در localStorage مرورگر نگهداری می‌شود، مانند client استاندارد Supabase. از تزریق اسکریپت/XSS با پرهیز از اسکریپت‌های شخص ثالث و بازبینی هر تغییر HTML محافظت کنید.
- data at rest در Supabase تحت حفاظت پروژهٔ Supabase است، اما payloadهای `JSONB` این نسخه end-to-end encrypted نیستند. برای E2EE به مدیریت کلید و طراحی بازیابی مستقل نیاز است.

## بررسی پیش از انتشار

```bash
node --check .\tools\check-index-js.mjs
```

این بررسی syntax جاوااسکریپت درون `index.html` را بدون اجرای برنامه انجام می‌دهد. سپس به‌صورت دستی این مسیرها را روی موبایل و دسکتاپ بررسی کنید:

1. کار آفلاین، ایجاد/ویرایش/حذف تسک و مشاهدهٔ صف sync.
2. ثبت‌نام با کد معتبر، کد منقضی/غیرفعال و سقف هم‌زمان.
3. ورود روی دستگاه جدید و دانلود داده‌ها.
4. انتقال دادهٔ قدیمی و عدم ایجاد duplicate با تکرار انتقال.
5. RLS با دو کاربر: هیچ درخواست مستقیم یا تغییر `user_id` نباید دادهٔ کاربر دیگر را برگرداند.
