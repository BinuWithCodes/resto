# RUNBOOK

One-page operations guide. Keep it current. Written to be followed by a
non-expert at 11 PM when something breaks.

## Restore a database backup

Backups are nightly `pg_dump` gzip files in Cloudflare R2 under `db/` (workflow:
`.github/workflows/backup.yml`). This is the ONLY backup — Supabase free has no
PITR.

1. List backups: `aws s3 ls s3://$R2_BUCKET/db/ --endpoint-url https://$R2_ACCOUNT_ID.r2.cloudflarestorage.com`
2. Download the chosen file: `aws s3 cp s3://$R2_BUCKET/db/<file> . --endpoint-url ...`
3. Restore into a target DB (test locally first!):
   `gunzip -c <file> | psql "$TARGET_DB_URL"`
4. For production restore: take a fresh dump first, then restore into a new
   Supabase project or the reset target. Never restore over prod without a
   current dump in hand.

## Resume a paused Supabase project

Free projects pause after 7 idle days. The keep-alive cron
(`/api/cron/keep-alive`, Vercel cron slot 1) prevents this. If it still paused:

1. Supabase dashboard → project → **Restore/Resume**.
2. Confirm `/api/health` returns `{ "db": "ok" }`.
3. Verify the keep-alive cron is enabled in Vercel and `CRON_SECRET` is set.

## Rotate keys

1. Supabase dashboard → Settings → API → roll the anon and/or service_role key.
2. Update Vercel env vars (`NEXT_PUBLIC_SUPABASE_ANON_KEY`,
   `SUPABASE_SERVICE_ROLE_KEY`) and redeploy.
3. Update GitHub secrets used by workflows (`SUPABASE_DB_URL` if the DB password
   changed).
4. Rotate `CRON_SECRET`, Upstash, and Sentry tokens the same way if exposed.

## Switch SMTP (auth emails)

Auth emails go through Brevo SMTP configured in Supabase Auth. To switch/repair:

1. Supabase dashboard → Authentication → SMTP settings → update host/port/user/pass.
2. Ensure SPF/DKIM for the sending domain are valid.
3. Send a test invite and confirm delivery (check Brevo logs).

## Roll back a Vercel deploy

1. Vercel dashboard → project → **Deployments**.
2. Find the last known-good deployment → **Promote to Production**.
3. If the rollback is due to a schema mismatch, also confirm the DB matches that
   deploy's expected migration state before promoting.

## Backup failed alert

The nightly backup workflow fails loudly (`::error::`) and GitHub emails the
repo owner. If it fails:

1. Open the failed run in Actions → read the step logs.
2. Common causes: expired `SUPABASE_DB_URL`, R2 credential rotation, Postgres
   major-version mismatch (the workflow pins `postgres:17`).
3. Re-run manually via **workflow_dispatch** once fixed; confirm the object
   appears in R2.
