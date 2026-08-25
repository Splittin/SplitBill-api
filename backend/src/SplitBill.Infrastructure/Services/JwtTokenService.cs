using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Options;
using SplitBill.Application;
using SplitBill.Application.DTOs;
using SplitBill.Application.Interfaces;

namespace SplitBill.Infrastructure.Services;

public class JwtTokenService : IJwtTokenService
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
    };

    private readonly JwtOptions _options;

    public JwtTokenService(IOptions<JwtOptions> options)
    {
        _options = options.Value;
    }

    public string CreateToken(UserDto user)
    {
        EnsureSigningKey();

        var hours = Math.Clamp(_options.ExpiryHours <= 0 ? 720 : _options.ExpiryHours, 1, 24 * 365);
        var payload = new AuthTokenPayload(
            user.UserId,
            user.Email,
            user.DisplayName,
            DateTimeOffset.UtcNow.ToUnixTimeSeconds(),
            DateTimeOffset.UtcNow.AddHours(hours).ToUnixTimeSeconds());

        var payloadJson = JsonSerializer.Serialize(payload, JsonOptions);
        var payloadPart = Base64UrlEncode(Encoding.UTF8.GetBytes(payloadJson));
        var signature = Sign(payloadPart);
        return $"{payloadPart}.{signature}";
    }

    public AuthTokenPayload? ValidateToken(string token)
    {
        EnsureSigningKey();

        var parts = token.Split('.', 2);
        if (parts.Length != 2)
        {
            return null;
        }

        var payloadPart = parts[0];
        var signature = parts[1];
        if (!FixedTimeEquals(signature, Sign(payloadPart)))
        {
            return null;
        }

        try
        {
            var json = Encoding.UTF8.GetString(Base64UrlDecode(payloadPart));
            var payload = JsonSerializer.Deserialize<AuthTokenPayload>(json, JsonOptions);
            if (payload is null)
            {
                return null;
            }

            if (payload.ExpiresAtUnix < DateTimeOffset.UtcNow.ToUnixTimeSeconds())
            {
                return null;
            }

            return payload;
        }
        catch
        {
            return null;
        }
    }

    private string Sign(string payloadPart)
    {
        var key = Encoding.UTF8.GetBytes(_options.SigningKey);
        var data = Encoding.UTF8.GetBytes(payloadPart);
        var hash = HMACSHA256.HashData(key, data);
        return Base64UrlEncode(hash);
    }

    private void EnsureSigningKey()
    {
        if (string.IsNullOrWhiteSpace(_options.SigningKey) || _options.SigningKey.Length < 32)
        {
            throw new InvalidOperationException("Jwt:SigningKey must be at least 32 characters.");
        }
    }

    private static bool FixedTimeEquals(string left, string right)
    {
        var a = Encoding.UTF8.GetBytes(left);
        var b = Encoding.UTF8.GetBytes(right);
        return a.Length == b.Length && CryptographicOperations.FixedTimeEquals(a, b);
    }

    private static string Base64UrlEncode(byte[] bytes) =>
        Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');

    private static byte[] Base64UrlDecode(string value)
    {
        var padded = value.Replace('-', '+').Replace('_', '/');
        switch (padded.Length % 4)
        {
            case 2: padded += "=="; break;
            case 3: padded += "="; break;
        }

        return Convert.FromBase64String(padded);
    }
}
