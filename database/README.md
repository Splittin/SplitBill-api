# Database (PostgreSQL)

Hosted schema is managed with the Supabase CLI (`supabase/migrations/`). The first migration was generated from the scripts in this folder.

For a new database change:

```bash
supabase migration new describe-the-change
# edit the file under supabase/migrations/
supabase db push
```

These `database/*.sql` scripts still run automatically on first `docker compose up` via `/docker-entrypoint-initdb.d` (local fallback).

Manual apply against an existing database:

```bash
psql "postgresql://splitbill:splitbill@localhost:5432/splitbill" -f 06_migrate_existing.sql
psql "postgresql://splitbill:splitbill@localhost:5432/splitbill" -f 02_functions_users.sql
psql "postgresql://splitbill:splitbill@localhost:5432/splitbill" -f 03_functions_bills.sql
psql "postgresql://splitbill:splitbill@localhost:5432/splitbill" -f 04_functions_groups.sql
psql "postgresql://splitbill:splitbill@localhost:5432/splitbill" -f 05_seed.sql
```

Fresh wipe + recreate:

```bash
docker compose down -v
docker compose up -d db
```

Start Postgres:

```bash
docker compose up -d db
```

Default connection (also in `appsettings.Development.json`):

`Host=localhost;Port=5432;Database=splitbill;Username=splitbill;Password=splitbill`
