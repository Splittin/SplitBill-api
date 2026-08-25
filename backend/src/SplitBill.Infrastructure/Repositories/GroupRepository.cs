using Dapper;
using Npgsql;
using SplitBill.Application.DTOs;
using SplitBill.Application.Interfaces;

namespace SplitBill.Infrastructure.Repositories;

public class GroupRepository : IGroupRepository
{
    private readonly IDbConnectionFactory _connectionFactory;

    public GroupRepository(IDbConnectionFactory connectionFactory)
    {
        _connectionFactory = connectionFactory;
    }

    public async Task<IReadOnlyList<GroupSummaryDto>> GetGroupsForUserAsync(
        long userId,
        CancellationToken cancellationToken = default)
    {
        await using var connection = (NpgsqlConnection)await _connectionFactory.CreateOpenConnectionAsync(cancellationToken);
        var groups = await connection.QueryAsync<GroupSummaryDto>(
            new CommandDefinition(
                "SELECT * FROM fn_get_groups_for_user(@UserId)",
                new { UserId = userId },
                cancellationToken: cancellationToken));
        return groups.AsList();
    }

    public async Task<bool> IsGroupMemberAsync(long groupId, long userId, CancellationToken cancellationToken = default)
    {
        await using var connection = (NpgsqlConnection)await _connectionFactory.CreateOpenConnectionAsync(cancellationToken);
        return await connection.ExecuteScalarAsync<bool>(
            new CommandDefinition(
                "SELECT fn_user_is_group_member(@GroupId, @UserId)",
                new { GroupId = groupId, UserId = userId },
                cancellationToken: cancellationToken));
    }

    public async Task<GroupDetailDto?> GetGroupByIdAsync(long groupId, CancellationToken cancellationToken = default)
    {
        await using var connection = (NpgsqlConnection)await _connectionFactory.CreateOpenConnectionAsync(cancellationToken);

        var summary = await connection.QuerySingleOrDefaultAsync<GroupSummaryDto>(
            new CommandDefinition(
                "SELECT * FROM fn_get_group_by_id(@GroupId)",
                new { GroupId = groupId },
                cancellationToken: cancellationToken));

        if (summary is null)
        {
            return null;
        }

        var members = await connection.QueryAsync<GroupMemberDto>(
            new CommandDefinition(
                "SELECT * FROM fn_get_group_members(@GroupId)",
                new { GroupId = groupId },
                cancellationToken: cancellationToken));

        return new GroupDetailDto(
            summary.GroupId,
            summary.Name,
            summary.CreatedByUserId,
            summary.CreatedAt,
            summary.MemberCount,
            summary.OpenBillCount,
            members.AsList());
    }

    public async Task<long> CreateGroupAsync(CreateGroupRequest request, CancellationToken cancellationToken = default)
    {
        await using var connection = (NpgsqlConnection)await _connectionFactory.CreateOpenConnectionAsync(cancellationToken);
        return await connection.ExecuteScalarAsync<long>(
            new CommandDefinition(
                "SELECT fn_create_group(@Name, @CreatedByUserId)",
                new { request.Name, request.CreatedByUserId },
                cancellationToken: cancellationToken));
    }

    public async Task AddMemberAsync(long groupId, long userId, CancellationToken cancellationToken = default)
    {
        await using var connection = (NpgsqlConnection)await _connectionFactory.CreateOpenConnectionAsync(cancellationToken);
        try
        {
            await connection.ExecuteAsync(
                new CommandDefinition(
                    "SELECT fn_add_group_member(@GroupId, @UserId)",
                    new { GroupId = groupId, UserId = userId },
                    cancellationToken: cancellationToken));
        }
        catch (PostgresException ex) when (ex.SqlState == PostgresErrorCodes.NoDataFound)
        {
            throw new KeyNotFoundException(ex.MessageText);
        }
    }

    public async Task RemoveMemberAsync(long groupId, long userId, CancellationToken cancellationToken = default)
    {
        await using var connection = (NpgsqlConnection)await _connectionFactory.CreateOpenConnectionAsync(cancellationToken);
        try
        {
            await connection.ExecuteAsync(
                new CommandDefinition(
                    "SELECT fn_remove_group_member(@GroupId, @UserId)",
                    new { GroupId = groupId, UserId = userId },
                    cancellationToken: cancellationToken));
        }
        catch (PostgresException ex) when (ex.SqlState == PostgresErrorCodes.NoDataFound)
        {
            throw new KeyNotFoundException(ex.MessageText);
        }
    }

    public async Task<IReadOnlyList<ShoppingItemDto>> GetShoppingItemsAsync(long groupId, CancellationToken cancellationToken = default)
    {
        await using var connection = (NpgsqlConnection)await _connectionFactory.CreateOpenConnectionAsync(cancellationToken);
        var items = await connection.QueryAsync<ShoppingItemDto>(
            new CommandDefinition(
                "SELECT * FROM fn_get_shopping_items(@GroupId)",
                new { GroupId = groupId },
                cancellationToken: cancellationToken));
        return items.AsList();
    }

    public async Task<IReadOnlyList<ShoppingItemDto>> GetShoppingItemsForUserAsync(
        long userId,
        CancellationToken cancellationToken = default)
    {
        await using var connection = (NpgsqlConnection)await _connectionFactory.CreateOpenConnectionAsync(cancellationToken);
        var items = await connection.QueryAsync<ShoppingItemDto>(
            new CommandDefinition(
                "SELECT * FROM fn_get_shopping_items_for_user(@UserId)",
                new { UserId = userId },
                cancellationToken: cancellationToken));
        return items.AsList();
    }

    public async Task<long> AddShoppingItemAsync(
        long groupId,
        CreateShoppingItemRequest request,
        CancellationToken cancellationToken = default)
    {
        await using var connection = (NpgsqlConnection)await _connectionFactory.CreateOpenConnectionAsync(cancellationToken);
        return await connection.ExecuteScalarAsync<long>(
            new CommandDefinition(
                """
                SELECT fn_add_shopping_item(
                    @GroupId, @Name, @AddedByUserId, @Quantity,
                    @Store, @Price, @Brand, @ProductUrl, @ImageUrl, @ProductId, @Unit)
                """,
                new
                {
                    GroupId = groupId,
                    request.Name,
                    request.AddedByUserId,
                    request.Quantity,
                    request.Store,
                    request.Price,
                    request.Brand,
                    request.ProductUrl,
                    request.ImageUrl,
                    request.ProductId,
                    request.Unit,
                },
                cancellationToken: cancellationToken));
    }

    public async Task<ShoppingItemDto?> GetShoppingItemAsync(long itemId, CancellationToken cancellationToken = default)
    {
        await using var connection = (NpgsqlConnection)await _connectionFactory.CreateOpenConnectionAsync(cancellationToken);
        var item = await connection.QuerySingleOrDefaultAsync<ShoppingItemDto>(
            new CommandDefinition(
                "SELECT * FROM fn_get_shopping_item(@ItemId)",
                new { ItemId = itemId },
                cancellationToken: cancellationToken));
        return item;
    }

    public async Task<ShoppingItemDto> UpdateShoppingItemAsync(
        long itemId,
        UpdateShoppingItemRequest request,
        CancellationToken cancellationToken = default)
    {
        await using var connection = (NpgsqlConnection)await _connectionFactory.CreateOpenConnectionAsync(cancellationToken);
        try
        {
            return await connection.QuerySingleAsync<ShoppingItemDto>(
                new CommandDefinition(
                    """
                    SELECT * FROM fn_update_shopping_item(
                        @ItemId, @Name, @IsChecked, @Quantity, @SetProduct,
                        @Store, @Price, @Brand, @ProductUrl, @ImageUrl, @ProductId, @Unit)
                    """,
                    new
                    {
                        ItemId = itemId,
                        request.Name,
                        request.IsChecked,
                        request.Quantity,
                        request.SetProduct,
                        request.Store,
                        request.Price,
                        request.Brand,
                        request.ProductUrl,
                        request.ImageUrl,
                        request.ProductId,
                        request.Unit,
                    },
                    cancellationToken: cancellationToken));
        }
        catch (PostgresException ex) when (ex.SqlState is PostgresErrorCodes.NoDataFound or "P0002")
        {
            throw new KeyNotFoundException($"Shopping item {itemId} not found.");
        }
        catch (PostgresException ex) when (ex.SqlState == "22023")
        {
            throw new ArgumentException(ex.MessageText);
        }
    }

    public async Task DeleteShoppingItemAsync(long itemId, CancellationToken cancellationToken = default)
    {
        await using var connection = (NpgsqlConnection)await _connectionFactory.CreateOpenConnectionAsync(cancellationToken);
        try
        {
            await connection.ExecuteAsync(
                new CommandDefinition(
                    "SELECT fn_delete_shopping_item(@ItemId)",
                    new { ItemId = itemId },
                    cancellationToken: cancellationToken));
        }
        catch (PostgresException ex) when (ex.SqlState is PostgresErrorCodes.NoDataFound or "P0002")
        {
            throw new KeyNotFoundException($"Shopping item {itemId} not found.");
        }
    }

    public async Task<int> ClearCheckedShoppingItemsAsync(long groupId, CancellationToken cancellationToken = default)
    {
        await using var connection = (NpgsqlConnection)await _connectionFactory.CreateOpenConnectionAsync(cancellationToken);
        return await connection.ExecuteScalarAsync<int>(
            new CommandDefinition(
                "SELECT fn_clear_checked_shopping_items(@GroupId)",
                new { GroupId = groupId },
                cancellationToken: cancellationToken));
    }

    public async Task<IReadOnlyList<ChatMessageDto>> GetChatMessagesAsync(long groupId, CancellationToken cancellationToken = default)
    {
        await using var connection = (NpgsqlConnection)await _connectionFactory.CreateOpenConnectionAsync(cancellationToken);
        var messages = await connection.QueryAsync<ChatMessageDto>(
            new CommandDefinition(
                "SELECT * FROM fn_get_chat_messages(@GroupId)",
                new { GroupId = groupId },
                cancellationToken: cancellationToken));
        return messages.AsList();
    }

    public async Task<long> AddChatMessageAsync(
        long groupId,
        CreateChatMessageRequest request,
        CancellationToken cancellationToken = default)
    {
        await using var connection = (NpgsqlConnection)await _connectionFactory.CreateOpenConnectionAsync(cancellationToken);
        return await connection.ExecuteScalarAsync<long>(
            new CommandDefinition(
                "SELECT fn_add_chat_message(@GroupId, @AuthorUserId, @Body)",
                new { GroupId = groupId, request.AuthorUserId, request.Body },
                cancellationToken: cancellationToken));
    }
}
