using SplitBill.Application.DTOs;
using SplitBill.Application.Interfaces;

namespace SplitBill.Application.Services;

public class GroupService
{
    private readonly IGroupRepository _groupRepository;

    public GroupService(IGroupRepository groupRepository)
    {
        _groupRepository = groupRepository;
    }

    public Task<IReadOnlyList<GroupSummaryDto>> GetGroupsForUserAsync(
        long userId,
        CancellationToken cancellationToken = default)
        => _groupRepository.GetGroupsForUserAsync(userId, cancellationToken);

    public Task<GroupDetailDto?> GetGroupByIdAsync(long groupId, CancellationToken cancellationToken = default)
        => _groupRepository.GetGroupByIdAsync(groupId, cancellationToken);

    public Task<bool> IsGroupMemberAsync(long groupId, long userId, CancellationToken cancellationToken = default)
        => _groupRepository.IsGroupMemberAsync(groupId, userId, cancellationToken);

    public async Task<long> CreateGroupAsync(long createdByUserId, string name, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(name))
        {
            throw new ArgumentException("Group name is required.", nameof(name));
        }

        if (createdByUserId <= 0)
        {
            throw new ArgumentException("User id must be positive.", nameof(createdByUserId));
        }

        return await _groupRepository.CreateGroupAsync(
            new CreateGroupRequest(name.Trim(), createdByUserId),
            cancellationToken);
    }

    public async Task AddMemberAsync(long groupId, AddGroupMemberRequest request, CancellationToken cancellationToken = default)
    {
        if (groupId <= 0 || request.UserId <= 0)
        {
            throw new ArgumentException("Group and user ids must be positive.");
        }

        await _groupRepository.AddMemberAsync(groupId, request.UserId, cancellationToken);
    }

    public async Task RemoveMemberAsync(long groupId, long userId, CancellationToken cancellationToken = default)
    {
        if (groupId <= 0 || userId <= 0)
        {
            throw new ArgumentException("Group and user ids must be positive.");
        }

        await _groupRepository.RemoveMemberAsync(groupId, userId, cancellationToken);
    }

    public Task<IReadOnlyList<ShoppingItemDto>> GetShoppingItemsAsync(long groupId, CancellationToken cancellationToken = default)
        => _groupRepository.GetShoppingItemsAsync(groupId, cancellationToken);

    public Task<IReadOnlyList<ShoppingItemDto>> GetShoppingItemsForUserAsync(
        long userId,
        CancellationToken cancellationToken = default)
        => _groupRepository.GetShoppingItemsForUserAsync(userId, cancellationToken);

    public async Task<long> AddShoppingItemAsync(
        long groupId,
        CreateShoppingItemRequest request,
        CancellationToken cancellationToken = default)
    {
        if (groupId <= 0)
        {
            throw new ArgumentException("Group id must be positive.", nameof(groupId));
        }

        if (string.IsNullOrWhiteSpace(request.Name))
        {
            throw new ArgumentException("Item name is required.", nameof(request));
        }

        if (request.AddedByUserId <= 0)
        {
            throw new ArgumentException("AddedByUserId must be positive.", nameof(request));
        }

        if (request.Quantity < 0)
        {
            throw new ArgumentException("Quantity must be zero or greater.", nameof(request));
        }

        return await _groupRepository.AddShoppingItemAsync(
            groupId,
            request with
            {
                Name = request.Name.Trim(),
                Quantity = request.Quantity <= 0 ? 1 : request.Quantity,
                Store = TrimOrNull(request.Store),
                Brand = TrimOrNull(request.Brand),
                ProductUrl = TrimOrNull(request.ProductUrl),
                ImageUrl = TrimOrNull(request.ImageUrl),
                ProductId = TrimOrNull(request.ProductId),
                Unit = TrimOrNull(request.Unit),
            },
            cancellationToken);
    }

    public Task<ShoppingItemDto?> GetShoppingItemAsync(long itemId, CancellationToken cancellationToken = default)
        => _groupRepository.GetShoppingItemAsync(itemId, cancellationToken);

    public Task<ShoppingItemDto> UpdateShoppingItemAsync(
        long itemId,
        UpdateShoppingItemRequest request,
        CancellationToken cancellationToken = default)
    {
        if (itemId <= 0)
        {
            throw new ArgumentException("Item id must be positive.", nameof(itemId));
        }

        if (request.Name is null
            && request.IsChecked is null
            && request.Quantity is null
            && !request.SetProduct)
        {
            throw new ArgumentException("At least one field is required.", nameof(request));
        }

        if (request.Name is not null && string.IsNullOrWhiteSpace(request.Name))
        {
            throw new ArgumentException("Item name cannot be empty.", nameof(request));
        }

        if (request.Quantity is < 0)
        {
            throw new ArgumentException("Quantity must be zero or greater.", nameof(request));
        }

        return _groupRepository.UpdateShoppingItemAsync(
            itemId,
            request with
            {
                Name = request.Name?.Trim(),
                Store = TrimOrNull(request.Store),
                Brand = TrimOrNull(request.Brand),
                ProductUrl = TrimOrNull(request.ProductUrl),
                ImageUrl = TrimOrNull(request.ImageUrl),
                ProductId = TrimOrNull(request.ProductId),
                Unit = TrimOrNull(request.Unit),
            },
            cancellationToken);
    }

    public Task DeleteShoppingItemAsync(long itemId, CancellationToken cancellationToken = default)
    {
        if (itemId <= 0)
        {
            throw new ArgumentException("Item id must be positive.", nameof(itemId));
        }

        return _groupRepository.DeleteShoppingItemAsync(itemId, cancellationToken);
    }

    public Task<int> ClearCheckedShoppingItemsAsync(long groupId, CancellationToken cancellationToken = default)
    {
        if (groupId <= 0)
        {
            throw new ArgumentException("Group id must be positive.", nameof(groupId));
        }

        return _groupRepository.ClearCheckedShoppingItemsAsync(groupId, cancellationToken);
    }

    public Task<IReadOnlyList<ChatMessageDto>> GetChatMessagesAsync(long groupId, CancellationToken cancellationToken = default)
        => _groupRepository.GetChatMessagesAsync(groupId, cancellationToken);

    public async Task<long> AddChatMessageAsync(
        long groupId,
        CreateChatMessageRequest request,
        CancellationToken cancellationToken = default)
    {
        if (groupId <= 0)
        {
            throw new ArgumentException("Group id must be positive.", nameof(groupId));
        }

        if (request.AuthorUserId <= 0)
        {
            throw new ArgumentException("AuthorUserId must be positive.", nameof(request));
        }

        if (string.IsNullOrWhiteSpace(request.Body))
        {
            throw new ArgumentException("Message body is required.", nameof(request));
        }

        return await _groupRepository.AddChatMessageAsync(
            groupId,
            request with { Body = request.Body.Trim() },
            cancellationToken);
    }

    private static string? TrimOrNull(string? value)
        => string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}
