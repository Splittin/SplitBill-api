using Dapper;
using Npgsql;
using SplitBill.Application.DTOs;
using SplitBill.Application.Interfaces;

namespace SplitBill.Infrastructure.Repositories;

public class AuthRepository : IAuthRepository
{
    private readonly IDbConnectionFactory _connectionFactory;

    public AuthRepository(IDbConnectionFactory connectionFactory)
    {
        _connectionFactory = connectionFactory;
    }

    public async Task CreateLoginOtpAsync(
        string email,
        string codeHash,
        DateTime expiresAt,
        CancellationToken cancellationToken = default)
    {
        await using var connection = (NpgsqlConnection)await _connectionFactory.CreateOpenConnectionAsync(cancellationToken);
        await connection.ExecuteScalarAsync<long>(
            new CommandDefinition(
                "SELECT fn_create_login_otp(@Email, @CodeHash, @ExpiresAt)",
                new { Email = email, CodeHash = codeHash, ExpiresAt = expiresAt },
                commandTimeout: 15,
                cancellationToken: cancellationToken));
    }

    public async Task<bool> ConsumeLoginOtpAsync(
        string email,
        string codeHash,
        CancellationToken cancellationToken = default)
    {
        await using var connection = (NpgsqlConnection)await _connectionFactory.CreateOpenConnectionAsync(cancellationToken);
        return await connection.ExecuteScalarAsync<bool>(
            new CommandDefinition(
                "SELECT fn_consume_login_otp(@Email, @CodeHash)",
                new { Email = email, CodeHash = codeHash },
                cancellationToken: cancellationToken));
    }

    public async Task<AuthUpsertResult> UpsertAuthUserAsync(
        string email,
        string displayName,
        string authProvider,
        string? googleSub = null,
        string? avatarUrl = null,
        CancellationToken cancellationToken = default)
    {
        await using var connection = (NpgsqlConnection)await _connectionFactory.CreateOpenConnectionAsync(cancellationToken);
        try
        {
            var row = await connection.QuerySingleAsync<AuthUserRow>(
                new CommandDefinition(
                    """
                    SELECT * FROM fn_upsert_auth_user(
                        @Email, @DisplayName, @AuthProvider, @GoogleSub, @AvatarUrl)
                    """,
                    new
                    {
                        Email = email,
                        DisplayName = displayName,
                        AuthProvider = authProvider,
                        GoogleSub = googleSub,
                        AvatarUrl = avatarUrl,
                    },
                    cancellationToken: cancellationToken));

            return new AuthUpsertResult(
                new UserDto(
                    row.UserId,
                    row.DisplayName,
                    row.Email,
                    row.AvatarUrl,
                    row.PayId,
                    row.BankName,
                    row.Bsb,
                    row.AccountNumber,
                    row.CreatedAt,
                    row.UpdatedAt),
                row.IsNewUser);
        }
        catch (PostgresException ex) when (ex.SqlState == "P0001")
        {
            throw new ArgumentException(ex.MessageText, ex);
        }
    }

    public async Task<UserDto?> GetUserByEmailAsync(string email, CancellationToken cancellationToken = default)
    {
        await using var connection = (NpgsqlConnection)await _connectionFactory.CreateOpenConnectionAsync(cancellationToken);
        return await connection.QuerySingleOrDefaultAsync<UserDto>(
            new CommandDefinition(
                "SELECT * FROM fn_get_user_by_email(@Email)",
                new { Email = email },
                cancellationToken: cancellationToken));
    }

    /// <summary>
    /// Class (not record) so Dapper can map even if IsNewUser is missing on older DBs.
    /// </summary>
    private sealed class AuthUserRow
    {
        public long UserId { get; set; }
        public string DisplayName { get; set; } = "";
        public string Email { get; set; } = "";
        public string? AvatarUrl { get; set; }
        public string? PayId { get; set; }
        public string? BankName { get; set; }
        public string? Bsb { get; set; }
        public string? AccountNumber { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime UpdatedAt { get; set; }
        public bool IsNewUser { get; set; }
    }
}
