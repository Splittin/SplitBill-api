using System.Data;
using Dapper;
using Npgsql;
using SplitBill.Application.DTOs;
using SplitBill.Application.Interfaces;

namespace SplitBill.Infrastructure.Repositories;

public class UserRepository : IUserRepository
{
    private readonly IDbConnectionFactory _connectionFactory;

    public UserRepository(IDbConnectionFactory connectionFactory)
    {
        _connectionFactory = connectionFactory;
    }

    public async Task<IReadOnlyList<UserDto>> GetUsersAsync(CancellationToken cancellationToken = default)
    {
        await using var connection = (NpgsqlConnection)await _connectionFactory.CreateOpenConnectionAsync(cancellationToken);

        var users = await connection.QueryAsync<UserDto>(
            new CommandDefinition(
                "SELECT * FROM fn_get_users()",
                cancellationToken: cancellationToken));

        return users.AsList();
    }

    public async Task<UserDto?> GetUserByIdAsync(long userId, CancellationToken cancellationToken = default)
    {
        await using var connection = (NpgsqlConnection)await _connectionFactory.CreateOpenConnectionAsync(cancellationToken);

        return await connection.QuerySingleOrDefaultAsync<UserDto>(
            new CommandDefinition(
                "SELECT * FROM fn_get_user_by_id(@UserId)",
                new { UserId = userId },
                cancellationToken: cancellationToken));
    }

    public async Task<long> CreateUserAsync(CreateUserRequest request, CancellationToken cancellationToken = default)
    {
        await using var connection = (NpgsqlConnection)await _connectionFactory.CreateOpenConnectionAsync(cancellationToken);

        return await connection.ExecuteScalarAsync<long>(
            new CommandDefinition(
                """
                SELECT fn_create_user(
                    @DisplayName,
                    @Email,
                    @PayId,
                    @BankName,
                    @Bsb,
                    @AccountNumber,
                    @AvatarUrl)
                """,
                request,
                cancellationToken: cancellationToken));
    }

    public async Task<UserDto> UpdateProfileAsync(
        long userId,
        UpdateUserProfileRequest request,
        CancellationToken cancellationToken = default)
    {
        await using var connection = (NpgsqlConnection)await _connectionFactory.CreateOpenConnectionAsync(cancellationToken);

        try
        {
            var updated = await connection.QuerySingleAsync<UserDto>(
                new CommandDefinition(
                    """
                    SELECT * FROM fn_update_user_profile(
                        @UserId,
                        @DisplayName,
                        @Email,
                        @AvatarUrl,
                        @PayId,
                        @BankName,
                        @Bsb,
                        @AccountNumber)
                    """,
                    new
                    {
                        UserId = userId,
                        request.DisplayName,
                        request.Email,
                        request.AvatarUrl,
                        request.PayId,
                        request.BankName,
                        request.Bsb,
                        request.AccountNumber
                    },
                    cancellationToken: cancellationToken));

            return updated;
        }
        catch (PostgresException ex) when (ex.SqlState == PostgresErrorCodes.NoDataFound || ex.SqlState == "P0002")
        {
            throw new KeyNotFoundException($"User {userId} was not found.", ex);
        }
    }
}
