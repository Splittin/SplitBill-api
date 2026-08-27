using System.Data;
using Microsoft.Extensions.Configuration;
using Npgsql;
using SplitBill.Application.Interfaces;

namespace SplitBill.Infrastructure.Persistence;

public class NpgsqlConnectionFactory : IDbConnectionFactory
{
    private readonly string _connectionString;

    public NpgsqlConnectionFactory(IConfiguration configuration)
    {
        var raw = configuration.GetConnectionString("PostgreSQL")
            ?? throw new InvalidOperationException("Connection string 'PostgreSQL' is not configured.");
        _connectionString = Normalize(raw);
    }

    public async Task<IDbConnection> CreateOpenConnectionAsync(CancellationToken cancellationToken = default)
    {
        var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        return connection;
    }

    /// <summary>
    /// PgBouncer / Supabase poolers reject prepared statements and hang on
    /// connection reset. Npgsql 10 prefers GSS/Kerberos by default, which
    /// fails in slim .NET container images without libgssapi_krb5.
    /// </summary>
    internal static string Normalize(string connectionString)
    {
        var builder = new NpgsqlConnectionStringBuilder(connectionString)
        {
            MaxAutoPrepare = 0,
            Multiplexing = false,
            GssEncryptionMode = GssEncryptionMode.Disable,
        };

        var host = builder.Host ?? "";
        var pooled = host.Contains("pooler", StringComparison.OrdinalIgnoreCase)
            || host.Contains("supabase.co", StringComparison.OrdinalIgnoreCase);
        if (pooled)
        {
            builder.NoResetOnClose = true;
            builder.SslMode = SslMode.Require;
            if (builder.Timeout < 15)
            {
                builder.Timeout = 15;
            }
        }

        return builder.ConnectionString;
    }
}
