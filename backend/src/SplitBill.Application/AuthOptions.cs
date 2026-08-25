namespace SplitBill.Application;

public class JwtOptions
{
    public const string SectionName = "Jwt";

    public string Issuer { get; set; } = "SplitBill";
    public string Audience { get; set; } = "SplitBill.Mobile";
    public string SigningKey { get; set; } = string.Empty;
    public int ExpiryHours { get; set; } = 720;
}

public class AuthOptions
{
    public const string SectionName = "Auth";

    /// <summary>
    /// When true, OTP codes are returned in the API response (dev / no-SMTP testing).
    /// </summary>
    public bool ExposeOtpInResponse { get; set; }

    public int OtpExpiryMinutes { get; set; } = 10;
}

public class GoogleAuthOptions
{
    public const string SectionName = "GoogleAuth";

    /// <summary>
    /// Accepted Google OAuth client IDs (Web / iOS / Android). Empty = Google login disabled.
    /// </summary>
    public string[] ClientIds { get; set; } = [];
}
