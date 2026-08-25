namespace SplitBill.Application;

public sealed class InviteOptions
{
    public string PublicAppBaseUrl { get; set; } = "http://localhost:8081";
    public int InviteExpiryDays { get; set; } = 7;
}
