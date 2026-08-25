using SplitBill.Application.DTOs;
using SplitBill.Application.Interfaces;

namespace SplitBill.Application.Services;

public class UserService
{
    private readonly IUserRepository _userRepository;

    public UserService(IUserRepository userRepository)
    {
        _userRepository = userRepository;
    }

    public Task<IReadOnlyList<UserDto>> GetUsersAsync(CancellationToken cancellationToken = default)
        => _userRepository.GetUsersAsync(cancellationToken);

    public async Task<UserDto?> GetUserByIdAsync(long userId, CancellationToken cancellationToken = default)
    {
        if (userId <= 0)
        {
            throw new ArgumentException("User id must be greater than zero.", nameof(userId));
        }

        return await _userRepository.GetUserByIdAsync(userId, cancellationToken);
    }

    public async Task<long> CreateUserAsync(CreateUserRequest request, CancellationToken cancellationToken = default)
    {
        ValidateIdentity(request.DisplayName, request.Email);
        return await _userRepository.CreateUserAsync(request, cancellationToken);
    }

    public async Task<UserDto> UpdateProfileAsync(
        long userId,
        UpdateUserProfileRequest request,
        CancellationToken cancellationToken = default)
    {
        if (userId <= 0)
        {
            throw new ArgumentException("User id must be greater than zero.", nameof(userId));
        }

        ValidateIdentity(request.DisplayName, request.Email);
        return await _userRepository.UpdateProfileAsync(userId, request, cancellationToken);
    }

    private static void ValidateIdentity(string displayName, string email)
    {
        if (string.IsNullOrWhiteSpace(displayName))
        {
            throw new ArgumentException("Display name is required.");
        }

        if (string.IsNullOrWhiteSpace(email) || !email.Contains('@'))
        {
            throw new ArgumentException("A valid email is required.");
        }
    }
}
