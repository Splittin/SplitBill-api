using System.Security.Claims;
using System.Text.Encodings.Web;
using Microsoft.AspNetCore.Authentication;
using Microsoft.Extensions.Options;
using SplitBill.Application.Interfaces;

namespace SplitBill.Api.Auth;

public static class SplitBillAuthDefaults
{
    public const string Scheme = "SplitBillBearer";
}

public sealed class SplitBillBearerOptions : AuthenticationSchemeOptions
{
}

public sealed class SplitBillBearerHandler : AuthenticationHandler<SplitBillBearerOptions>
{
    private readonly IJwtTokenService _tokenService;

    public SplitBillBearerHandler(
        IOptionsMonitor<SplitBillBearerOptions> options,
        ILoggerFactory logger,
        UrlEncoder encoder,
        IJwtTokenService tokenService)
        : base(options, logger, encoder)
    {
        _tokenService = tokenService;
    }

    protected override Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        if (!Request.Headers.TryGetValue("Authorization", out var headerValues))
        {
            return Task.FromResult(AuthenticateResult.NoResult());
        }

        var header = headerValues.ToString();
        if (string.IsNullOrWhiteSpace(header) ||
            !header.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
        {
            return Task.FromResult(AuthenticateResult.NoResult());
        }

        var token = header["Bearer ".Length..].Trim();
        if (string.IsNullOrWhiteSpace(token))
        {
            return Task.FromResult(AuthenticateResult.Fail("Missing bearer token."));
        }

        var payload = _tokenService.ValidateToken(token);
        if (payload is null)
        {
            return Task.FromResult(AuthenticateResult.Fail("Invalid or expired token."));
        }

        var claims = new[]
        {
            new Claim(ClaimTypes.NameIdentifier, payload.UserId.ToString()),
            new Claim("sub", payload.UserId.ToString()),
            new Claim(ClaimTypes.Email, payload.Email),
            new Claim(ClaimTypes.Name, payload.DisplayName),
        };

        var identity = new ClaimsIdentity(claims, SplitBillAuthDefaults.Scheme);
        var principal = new ClaimsPrincipal(identity);
        var ticket = new AuthenticationTicket(principal, SplitBillAuthDefaults.Scheme);
        return Task.FromResult(AuthenticateResult.Success(ticket));
    }
}
