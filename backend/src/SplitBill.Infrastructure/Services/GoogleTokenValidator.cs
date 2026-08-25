using System.Text.Json;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using SplitBill.Application;
using SplitBill.Application.Interfaces;

namespace SplitBill.Infrastructure.Services;

public class GoogleTokenValidator : IGoogleTokenValidator
{
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly GoogleAuthOptions _options;
    private readonly ILogger<GoogleTokenValidator> _logger;

    public GoogleTokenValidator(
        IHttpClientFactory httpClientFactory,
        IOptions<GoogleAuthOptions> options,
        ILogger<GoogleTokenValidator> logger)
    {
        _httpClientFactory = httpClientFactory;
        _options = options.Value;
        _logger = logger;
    }

    public async Task<GoogleIdentity?> ValidateAsync(string idToken, CancellationToken cancellationToken = default)
    {
        var client = _httpClientFactory.CreateClient(nameof(GoogleTokenValidator));
        using var response = await client.GetAsync(
            $"https://oauth2.googleapis.com/tokeninfo?id_token={Uri.EscapeDataString(idToken)}",
            cancellationToken);

        if (!response.IsSuccessStatusCode)
        {
            var body = await response.Content.ReadAsStringAsync(cancellationToken);
            _logger.LogWarning(
                "Google tokeninfo rejected id token ({Status}): {Body}",
                response.StatusCode,
                body.Length > 300 ? body[..300] : body);
            return null;
        }

        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        using var doc = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken);
        var root = doc.RootElement;

        var sub = root.TryGetProperty("sub", out var subEl) ? subEl.GetString() : null;
        var email = root.TryGetProperty("email", out var emailEl) ? emailEl.GetString() : null;
        if (string.IsNullOrWhiteSpace(sub) || string.IsNullOrWhiteSpace(email))
        {
            _logger.LogWarning("Google tokeninfo response missing sub/email");
            return null;
        }

        var aud = root.TryGetProperty("aud", out var audEl) ? audEl.GetString() : null;
        var allowed = _options.ClientIds
            .Where(id => !string.IsNullOrWhiteSpace(id))
            .Select(id => id.Trim())
            .ToHashSet(StringComparer.Ordinal);

        if (allowed.Count == 0)
        {
            _logger.LogWarning("GoogleAuth:ClientIds is empty — rejecting token");
            return null;
        }

        if (aud is null || !allowed.Contains(aud))
        {
            _logger.LogWarning(
                "Google token audience {Aud} is not in configured ClientIds [{Allowed}]",
                aud,
                string.Join(", ", allowed));
            return null;
        }

        var verified = false;
        if (root.TryGetProperty("email_verified", out var verifiedEl))
        {
            verified = verifiedEl.ValueKind switch
            {
                JsonValueKind.True => true,
                JsonValueKind.False => false,
                JsonValueKind.String => string.Equals(verifiedEl.GetString(), "true", StringComparison.OrdinalIgnoreCase),
                _ => false,
            };
        }

        var name = root.TryGetProperty("name", out var nameEl) ? nameEl.GetString() : null;
        var picture = root.TryGetProperty("picture", out var picEl) ? picEl.GetString() : null;

        return new GoogleIdentity(sub, email, name, picture, verified);
    }
}
