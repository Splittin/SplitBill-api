using SplitBill.Application.DTOs;

namespace SplitBill.Application.Interfaces;

public interface IUserRepository
{
    Task<IReadOnlyList<UserDto>> GetUsersAsync(CancellationToken cancellationToken = default);
    Task<UserDto?> GetUserByIdAsync(long userId, CancellationToken cancellationToken = default);
    Task<long> CreateUserAsync(CreateUserRequest request, CancellationToken cancellationToken = default);
    Task<UserDto> UpdateProfileAsync(long userId, UpdateUserProfileRequest request, CancellationToken cancellationToken = default);
}
