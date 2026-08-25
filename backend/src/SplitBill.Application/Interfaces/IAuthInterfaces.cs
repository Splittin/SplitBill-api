using SplitBill.Application.DTOs;

namespace SplitBill.Application.Interfaces;

public interface IAuthRepository
{
    Task CreateLoginOtpAsync(string email, string codeHash, DateTime expiresAt, CancellationToken cancellationToken = default);

    Task<bool> ConsumeLoginOtpAsync(string email, string codeHash, CancellationToken cancellationToken = default);

    Task<AuthUpsertResult> UpsertAuthUserAsync(
        string email,
        string displayName,
        string authProvider,
        string? googleSub = null,
        string? avatarUrl = null,
        CancellationToken cancellationToken = default);

    Task<UserDto?> GetUserByEmailAsync(string email, CancellationToken cancellationToken = default);
}

public record AuthUpsertResult(UserDto User, bool IsNewUser);

public interface IJwtTokenService
{
    string CreateToken(UserDto user);

    AuthTokenPayload? ValidateToken(string token);
}

public record AuthTokenPayload(
    long UserId,
    string Email,
    string DisplayName,
    long IssuedAtUnix,
    long ExpiresAtUnix);

public interface IGoogleTokenValidator
{
    Task<GoogleIdentity?> ValidateAsync(string idToken, CancellationToken cancellationToken = default);
}

public record GoogleIdentity(
    string Subject,
    string Email,
    string? Name,
    string? PictureUrl,
    bool EmailVerified);
