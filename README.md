# SplitBill API

ASP.NET Core 10 API + PostgreSQL (Supabase) for the SplitBill mobile app.

## Stack

| Layer | Tech |
| --- | --- |
| API | ASP.NET Core 10 (Clean Architecture) |
| Data | Supabase PostgreSQL (SQL functions via Dapper) |

## Project structure

```text
SplitBill-api/
├── backend/                # .NET solution
│   └── src/
│       ├── SplitBill.Api
│       ├── SplitBill.Application
│       ├── SplitBill.Domain
│       └── SplitBill.Infrastructure
├── database/               # Historical SQL scripts (source for first migration)
├── supabase/               # Supabase CLI config + migrations
└── docker-compose.yml      # Optional local PostgreSQL
```

## Prerequisites

- [.NET 10 SDK](https://dotnet.microsoft.com/download)
- [Supabase CLI](https://supabase.com/docs/guides/local-development/cli/getting-started)
- [Docker](https://www.docker.com/) (optional local Postgres)

## Quick start

### 1. Database

Copy `.env.example` to `.env` and fill in your Supabase credentials.

```bash
supabase login
supabase link --project-ref <your-project-ref>
supabase db push
```

If the direct DB host is IPv6-only on your network, use the **Session pooler** URI (port `6543`) in `ConnectionStrings__PostgreSQL` and add `SSL Mode=Require;Trust Server Certificate=true;Max Auto Prepare=0`.

Local fallback:

```bash
docker compose up -d db
```

### 2. API

```bash
cd backend
dotnet restore
dotnet run --project src/SplitBill.Api
```

- API: http://localhost:5080
- Swagger: http://localhost:5080/swagger

The API loads connection settings from the repo-root `.env` file.

## Deploy (Docker)

Root `Dockerfile` builds and runs the API. Set these env vars on the host (do not bake secrets into the image):

| Variable | Purpose |
| --- | --- |
| `ConnectionStrings__PostgreSQL` | Supabase / Postgres connection string |
| `Jwt__SigningKey` | JWT signing key (min 32 chars) |
| `PORT` | HTTP port (set automatically by Railway/Render) |

```bash
docker build -t splitbill-api .
docker run --rm -p 8080:8080 --env-file .env splitbill-api
```

## Scripts

| Command | Description |
| --- | --- |
| `supabase db push` | Apply migrations to the linked Supabase project |
| `docker compose up -d db` | Start local PostgreSQL (optional) |
| `dotnet run --project backend/src/SplitBill.Api` | Run API |
