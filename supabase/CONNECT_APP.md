# Connect The HTML App To Supabase

Open:

`assets/supabase-client.js`

Replace these two values:

```js
SUPABASE_URL: 'PASTE_YOUR_SUPABASE_PROJECT_URL_HERE',
SUPABASE_ANON_KEY: 'PASTE_YOUR_SUPABASE_ANON_KEY_HERE',
```

Use values from Supabase:

1. Project Settings
2. API
3. Project URL
4. Project API keys
5. `anon public`

After that, reload the HTML pages in the browser.

## Pages Wired First

- `registerstudent.html` saves students to Supabase.
- `studentperprogram.html` loads students from Supabase.
- `cass.html` loads classes, students, subjects, and assessment modes from Supabase.
- `documentmanager.html` loads student/staff owners and uploads files to Supabase Storage.

