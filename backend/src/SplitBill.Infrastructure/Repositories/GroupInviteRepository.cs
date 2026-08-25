using Dapper;
using Npgsql;
using SplitBill.Application.DTOs;
using SplitBill.Application.Interfaces;

namespace SplitBill.Infrastructure.Repositories;

public class GroupInviteRepository : IGroupInviteRepository
{
    private readonly IDbConnectionFactory _connectionFactory;

    public GroupInviteRepository(IDbConnectionFactory connectionFactory)
    {
        _connectionFactory = connectionFactory;
    }

    public async Task<GroupInviteRecord> CreateInviteAsync(
        long groupId,
        string email,
        string token,
        long invitedByUserId,
        DateTime expiresAt,
        CancellationToken cancellationToken = default)
    {
        await using var connection = (NpgsqlConnection)await _connectionFactory.CreateOpenConnectionAsync(cancellationToken);
        try
        {
            return await connection.QuerySingleAsync<GroupInviteRecord>(
                new CommandDefinition(
                    """
                    SELECT * FROM fn_create_group_invite(
                        @GroupId, @Email, @Token, @InvitedByUserId, @ExpiresAt)
                    """,
                    new
                    {
                        GroupId = groupId,
                        Email = email,
                        Token = token,
                        InvitedByUserId = invitedByUserId,
                        ExpiresAt = expiresAt,
                    },
                    cancellationToken: cancellationToken));
        }
        catch (PostgresException ex) when (ex.SqlState == PostgresErrorCodes.NoDataFound || ex.SqlState == "P0002")
        {
            throw new KeyNotFoundException(ex.MessageText, ex);
        }
        catch (PostgresException ex) when (ex.SqlState == "P0001")
        {
            throw new ArgumentException(ex.MessageText, ex);
        }
    }

    public async Task<GroupInviteLookup?> GetByTokenAsync(string token, CancellationToken cancellationToken = default)
    {
        await using var connection = (NpgsqlConnection)await _connectionFactory.CreateOpenConnectionAsync(cancellationToken);
        return await connection.QuerySingleOrDefaultAsync<GroupInviteLookup>(
            new CommandDefinition(
                "SELECT * FROM fn_get_group_invite_by_token(@Token)",
                new { Token = token },
                cancellationToken: cancellationToken));
    }

    public async Task<AcceptInviteResult> AcceptForUserAsync(
        string token,
        long userId,
        CancellationToken cancellationToken = default)
    {
        await using var connection = (NpgsqlConnection)await _connectionFactory.CreateOpenConnectionAsync(cancellationToken);
        try
        {
            return await connection.QuerySingleAsync<AcceptInviteResult>(
                new CommandDefinition(
                    "SELECT * FROM fn_accept_group_invite_for_user(@Token, @UserId)",
                    new { Token = token, UserId = userId },
                    cancellationToken: cancellationToken));
        }
        catch (PostgresException ex) when (ex.SqlState == PostgresErrorCodes.NoDataFound || ex.SqlState == "P0002")
        {
            throw new KeyNotFoundException(ex.MessageText, ex);
        }
        catch (PostgresException ex) when (ex.SqlState == "P0001")
        {
            throw new ArgumentException(ex.MessageText, ex);
        }
    }
}
