using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Options;
using SplitBill.Application.DTOs;
using SplitBill.Application.Interfaces;

namespace SplitBill.Application.Services;

public class AuthService
{
    private readonly IAuthRepository _authRepository;
    private readonly IJwtTokenService _jwtTokenService;
    private readonly IGoogleTokenValidator _googleTokenValidator;
    private readonly IEmailSender _emailSender;
    private readonly AuthOptions _authOptions;
    private readonly GoogleAuthOptions _googleOptions;

    public AuthService(
        IAuthRepository authRepository,
        IJwtTokenService jwtTokenService,
        IGoogleTokenValidator googleTokenValidator,
        IEmailSender emailSender,
        IOptions<AuthOptions> authOptions,
        IOptions<GoogleAuthOptions> googleOptions)
    {
        _authRepository = authRepository;
        _jwtTokenService = jwtTokenService;
        _googleTokenValidator = googleTokenValidator;
        _emailSender = emailSender;
        _authOptions = authOptions.Value;
        _googleOptions = googleOptions.Value;
    }

    public async Task<RequestEmailOtpResponse> RequestEmailOtpAsync(
        RequestEmailOtpRequest request,
        CancellationToken cancellationToken = default)
    {
        var email = NormalizeEmail(request.Email);
        var code = CreateOtpCode();
        var hash = HashOtp(email, code);
        var minutes = Math.Clamp(_authOptions.OtpExpiryMinutes <= 0 ? 10 : _authOptions.OtpExpiryMinutes, 1, 60);
        var expiresAt = DateTime.UtcNow.AddMinutes(minutes);

        await _authRepository.CreateLoginOtpAsync(email, hash, expiresAt, cancellationToken);

        var emailResult = await _emailSender.SendAsync(BuildOtpEmail(email, code, minutes), cancellationToken);

        var detail = emailResult.Sent
            ? "Check your email for a login code."
            : emailResult.Detail ?? "Could not send email. Use the development code if shown.";

        // When SMTP is off, always expose the code so local/dev login works.
        var exposeCode = _authOptions.ExposeOtpInResponse || !emailResult.Sent;

        return new RequestEmailOtpResponse(
            emailResult.Sent,
            detail,
            exposeCode ? code : null);
    }

    public async Task<AuthResponse> VerifyEmailOtpAsync(
        VerifyEmailOtpRequest request,
        CancellationToken cancellationToken = default)
    {
        var email = NormalizeEmail(request.Email);
        var code = (request.Code ?? string.Empty).Trim();
        if (code.Length < 4)
        {
            throw new ArgumentException("Enter the code from your email.");
        }

        var ok = await _authRepository.ConsumeLoginOtpAsync(email, HashOtp(email, code), cancellationToken);
        if (!ok)
        {
            throw new UnauthorizedAccessException("Invalid or expired code.");
        }

        var displayName = string.IsNullOrWhiteSpace(request.DisplayName)
            ? DeriveDisplayName(email)
            : request.DisplayName.Trim();

        var upsert = await _authRepository.UpsertAuthUserAsync(
            email,
            displayName,
            "email",
            cancellationToken: cancellationToken);

        return new AuthResponse(_jwtTokenService.CreateToken(upsert.User), upsert.User, upsert.IsNewUser);
    }

    public async Task<AuthResponse> GoogleLoginAsync(
        GoogleLoginRequest request,
        CancellationToken cancellationToken = default)
    {
        if (_googleOptions.ClientIds is not { Length: > 0 })
        {
            throw new InvalidOperationException("Google login is not configured on the server.");
        }

        if (string.IsNullOrWhiteSpace(request.IdToken))
        {
            throw new ArgumentException("Google id token is required.");
        }

        var identity = await _googleTokenValidator.ValidateAsync(request.IdToken.Trim(), cancellationToken);
        if (identity is null)
        {
            throw new UnauthorizedAccessException("Google sign-in could not be verified.");
        }

        if (!identity.EmailVerified)
        {
            throw new UnauthorizedAccessException("Google email is not verified.");
        }

        var email = NormalizeEmail(identity.Email);
        var displayName = string.IsNullOrWhiteSpace(identity.Name)
            ? DeriveDisplayName(email)
            : identity.Name.Trim();

        var upsert = await _authRepository.UpsertAuthUserAsync(
            email,
            displayName,
            "google",
            identity.Subject,
            identity.PictureUrl,
            cancellationToken);

        return new AuthResponse(_jwtTokenService.CreateToken(upsert.User), upsert.User, upsert.IsNewUser);
    }

    private static EmailMessage BuildOtpEmail(string email, string code, int minutes)
    {
        var subject = "Your SplitBill login code";
        var text = $"""
            Your SplitBill login code is {code}.

            It expires in {minutes} minutes. If you did not request this, you can ignore this email.
            """;
        var html = $"""
            <p>Your SplitBill login code is:</p>
            <p style="font-size:28px;font-weight:700;letter-spacing:4px;">{System.Net.WebUtility.HtmlEncode(code)}</p>
            <p style="color:#666;font-size:13px;">Expires in {minutes} minutes.</p>
            """;
        return new EmailMessage(email, subject, html, text);
    }

    private static string NormalizeEmail(string email)
    {
        if (string.IsNullOrWhiteSpace(email) || !email.Contains('@', StringComparison.Ordinal))
        {
            throw new ArgumentException("A valid email address is required.");
        }

        return email.Trim().ToLowerInvariant();
    }

    private static string DeriveDisplayName(string email)
    {
        var local = email.Split('@')[0];
        if (string.IsNullOrWhiteSpace(local))
        {
            return "Member";
        }

        var parts = local.Replace('.', ' ').Replace('_', ' ').Replace('-', ' ').Split(' ', StringSplitOptions.RemoveEmptyEntries);
        return string.Join(' ', parts.Select(p =>
            p.Length == 0 ? p : char.ToUpperInvariant(p[0]) + p[1..].ToLowerInvariant()));
    }

    private static string CreateOtpCode()
    {
        var value = RandomNumberGenerator.GetInt32(0, 1_000_000);
        return value.ToString("D6");
    }

    private static string HashOtp(string email, string code)
    {
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes($"{email}:{code}"));
        return Convert.ToHexString(bytes).ToLowerInvariant();
    }
}
