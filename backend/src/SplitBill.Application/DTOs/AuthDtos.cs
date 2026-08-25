namespace SplitBill.Application.DTOs;

public record RequestEmailOtpRequest(string Email);

public record RequestEmailOtpResponse(
    bool Sent,
    string? Detail,
    string? DevCode = null);

public record VerifyEmailOtpRequest(
    string Email,
    string Code,
    string? DisplayName = null);

public record GoogleLoginRequest(string IdToken);

public record AuthResponse(
    string AccessToken,
    UserDto User,
    bool IsNewUser = false);
