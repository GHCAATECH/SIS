# Supabase Setup

Use these migration files in order:

1. `supabase/migrations/20260621212900_create_axiombyte_sms_schema.sql`
2. `supabase/migrations/20260621213000_seed_axiombyte_sms.sql`

## Option 1: Supabase SQL Editor

1. Open your Supabase project.
2. Go to SQL Editor.
3. Open `20260621212900_create_axiombyte_sms_schema.sql`.
4. Paste all SQL and run it.
5. Open `20260621213000_seed_axiombyte_sms.sql`.
6. Paste all SQL and run it.

## Option 2: Supabase CLI

If your project is linked locally:

```bash
supabase db push
```

## Storage Buckets Needed Later

Create these buckets when we wire file uploads:

- `student-passports`
- `student-documents`
- `staff-documents`

