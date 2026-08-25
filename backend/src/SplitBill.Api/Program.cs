using SplitBill.Api.Auth;
using SplitBill.Application;
using SplitBill.Infrastructure;

LoadRepoDotEnv();
EnsureSupabaseConnectionString();

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

builder.Services.Configure<InviteOptions>(builder.Configuration.GetSection("App"));
builder.Services.Configure<JwtOptions>(builder.Configuration.GetSection(JwtOptions.SectionName));
builder.Services.Configure<AuthOptions>(builder.Configuration.GetSection(AuthOptions.SectionName));
builder.Services.Configure<GoogleAuthOptions>(builder.Configuration.GetSection(GoogleAuthOptions.SectionName));

builder.Services
    .AddAuthentication(SplitBillAuthDefaults.Scheme)
    .AddScheme<SplitBillBearerOptions, SplitBillBearerHandler>(SplitBillAuthDefaults.Scheme, _ => { });

builder.Services.AddAuthorization();
builder.Services.AddApplication();
builder.Services.AddInfrastructure();

builder.Services.AddCors(options =>
{
    options.AddPolicy("MobileClient", policy =>
        policy.AllowAnyHeader()
              .AllowAnyMethod()
              .AllowAnyOrigin());
});

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseCors("MobileClient");
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();

app.Run();

static void LoadRepoDotEnv()
{
    foreach (var start in new[] { Directory.GetCurrentDirectory(), AppContext.BaseDirectory })
    {
        for (var dir = new DirectoryInfo(start); dir is not null; dir = dir.Parent)
        {
            var envPath = Path.Combine(dir.FullName, ".env");
            if (!File.Exists(envPath))
            {
                continue;
            }

            foreach (var raw in File.ReadAllLines(envPath))
            {
                var line = raw.Trim();
                if (line.Length == 0 || line.StartsWith('#') || !line.Contains('='))
                {
                    continue;
                }

                if (line.StartsWith("export ", StringComparison.Ordinal))
                {
                    line = line["export ".Length..].Trim();
                }

                var idx = line.IndexOf('=');
                var key = line[..idx].Trim();
                var value = line[(idx + 1)..].Trim();
                if (value.Length >= 2 &&
                    ((value.StartsWith('"') && value.EndsWith('"')) ||
                     (value.StartsWith('\'') && value.EndsWith('\''))))
                {
                    value = value[1..^1];
                }

                if (!string.IsNullOrEmpty(key) &&
                    string.IsNullOrEmpty(Environment.GetEnvironmentVariable(key)))
                {
                    Environment.SetEnvironmentVariable(key, value);
                }
            }

            return;
        }
    }
}

static void EnsureSupabaseConnectionString()
{
    if (!string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("ConnectionStrings__PostgreSQL")))
    {
        return;
    }

    var password = FirstEnv("SUPABASE_DB_PASSWORD", "supabase_password");
    if (string.IsNullOrWhiteSpace(password))
    {
        return;
    }

    var projectRef = FirstEnv("SUPABASE_PROJECT_REF", "supabase_project_ref")
        ?? "nldexiszhilnxkqehdeb";
    var host = FirstEnv("SUPABASE_DB_HOST", "supabase_db_host")
        ?? $"db.{projectRef}.supabase.co";
    var port = FirstEnv("SUPABASE_DB_PORT", "supabase_db_port") ?? "5432";
    var database = FirstEnv("SUPABASE_DB_NAME", "supabase_db_name") ?? "postgres";
    var username = FirstEnv("SUPABASE_DB_USER", "supabase_db_user") ?? "postgres";

    Environment.SetEnvironmentVariable(
        "ConnectionStrings__PostgreSQL",
        $"Host={host};Port={port};Database={database};Username={username};Password={password};SSL Mode=Require;Trust Server Certificate=true");
}

static string? FirstEnv(params string[] keys)
{
    foreach (var key in keys)
    {
        var value = Environment.GetEnvironmentVariable(key);
        if (!string.IsNullOrWhiteSpace(value))
        {
            return value;
        }
    }

    return null;
}
