using SplitBill.Application.DTOs;

namespace SplitBill.Application.Interfaces;

public interface IGroupRepository
{
    Task<IReadOnlyList<GroupSummaryDto>> GetGroupsForUserAsync(long userId, CancellationToken cancellationToken = default);
    Task<GroupDetailDto?> GetGroupByIdAsync(long groupId, CancellationToken cancellationToken = default);
    Task<bool> IsGroupMemberAsync(long groupId, long userId, CancellationToken cancellationToken = default);
    Task<long> CreateGroupAsync(CreateGroupRequest request, CancellationToken cancellationToken = default);
    Task AddMemberAsync(long groupId, long userId, CancellationToken cancellationToken = default);
    Task RemoveMemberAsync(long groupId, long userId, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<ShoppingItemDto>> GetShoppingItemsAsync(long groupId, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<ShoppingItemDto>> GetShoppingItemsForUserAsync(long userId, CancellationToken cancellationToken = default);
    Task<long> AddShoppingItemAsync(long groupId, CreateShoppingItemRequest request, CancellationToken cancellationToken = default);
    Task<ShoppingItemDto?> GetShoppingItemAsync(long itemId, CancellationToken cancellationToken = default);
    Task<ShoppingItemDto> UpdateShoppingItemAsync(long itemId, UpdateShoppingItemRequest request, CancellationToken cancellationToken = default);
    Task DeleteShoppingItemAsync(long itemId, CancellationToken cancellationToken = default);
    Task<int> ClearCheckedShoppingItemsAsync(long groupId, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<ChatMessageDto>> GetChatMessagesAsync(long groupId, CancellationToken cancellationToken = default);
    Task<long> AddChatMessageAsync(long groupId, CreateChatMessageRequest request, CancellationToken cancellationToken = default);
}
