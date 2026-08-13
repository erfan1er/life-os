# اتصال Planer به Apple Reminders

این اتصال برای iPhone و iPad است. Planer دسترسی مستقیم به Reminders ندارد؛ در عوض، کارهای بازِ تاریخ‌دار را به‌صورت دادهٔ محلی به Shortcut شخصی شما می‌دهد. پس از راه‌اندازی، در Planer از مسیر **تنظیمات → Apple Reminders → ارسال کارها به Reminders** فقط یک دکمه می‌زنید.

## راه‌اندازی یک‌باره

1. روی iPhone یا iPad، برنامهٔ **Shortcuts** را باز کنید و `+` را بزنید.
2. نام Shortcut را دقیقاً این بگذارید:

   ```text
   Planer to Reminders
   ```

3. این اکشن‌ها را به‌ترتیب اضافه کنید. نام انگلیسی اکشن‌ها در جست‌وجوی Shortcuts قابل استفاده است:

   1. **Get Dictionary from Input**
   2. **Get Dictionary Value** با کلید `items`
   3. **Repeat with Each** روی خروجی مرحلهٔ قبل
   4. داخل Repeat:
      - **Get Dictionary Value** از `Repeat Item` با کلید `title`
      - **Get Dictionary Value** از `Repeat Item` با کلید `due`
      - **Get Dates from Input** روی مقدار `due`
      - **Get Dictionary Value** از `Repeat Item` با کلید `notes`
      - **Add New Reminder**
        - Title: مقدار `title`
        - Due Date: خروجی `Get Dates from Input`
        - Notes: مقدار `notes`

4. Shortcut را یک‌بار اجرا کنید و اجازهٔ دسترسی به **Reminders** را تأیید کنید. در صورت نیاز، فهرست مقصد را در اکشن **Add New Reminder** انتخاب کنید.

Apple URL scheme برای Shortcut از ورودی Clipboard پشتیبانی می‌کند؛ Planer از همین روش استفاده می‌کند تا ارسال تعداد زیادی کار به محدودیت طول URL نخورد.

## جلوگیری از تکرار (پیشنهادی)

هر آیتم یک مقدار یکتا با نام `marker` دارد و همین مقدار داخل یادداشت Reminder هم نوشته می‌شود.

پیش از **Add New Reminder** درون Repeat می‌توانید این منطق را اضافه کنید:

1. **Get Dictionary Value** از `Repeat Item` با کلید `marker`.
2. **Find Reminders** با شرطی که Notes شامل مقدار `marker` باشد.
3. فقط اگر هیچ نتیجه‌ای نبود، **Add New Reminder** را اجرا کنید.

این کار باعث می‌شود با زدن دوبارهٔ دکمهٔ Planer، Reminder تکراری ساخته نشود.

## چه چیزی منتقل می‌شود؟

- فقط کارهای انجام‌نشده‌ای که تاریخ دارند.
- عنوان، تاریخ و ساعت (اگر ثبت شده باشد)، و توضیح/یادداشت کار.
- داده ابتدا فقط در Clipboard همان دستگاه قرار می‌گیرد و بعد به Shortcut شما تحویل می‌شود؛ Planer برای این قابلیت از سرور یا کلید جدیدی استفاده نمی‌کند.

کارهای تکرارشونده در این نسخه به‌صورت یک Reminder برای تاریخ فعلی‌شان فرستاده می‌شوند. تغییر یا تکمیل Reminder در Apple Reminders به Planer برنمی‌گردد؛ این اتصال یک‌طرفه است.
