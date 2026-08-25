using SplitBill.Application.DTOs;

namespace SplitBill.Application.Interfaces;

public interface IGroupInviteRepository
{
    Task<GroupInviteRecord> CreateInviteAsync(
        long groupId,
        string email,
        string token,
        long invitedByUserId,
        DateTime expiresAt,
        CancellationToken cancellationToken = default);

    Task<GroupInviteLookup?> GetByTokenAsync(string token, CancellationToken cancellationToken = default);

    Task<AcceptInviteResult> AcceptForUserAsync(
        string token,
        long userId,
        CancellationToken cancellationToken = default);
}
