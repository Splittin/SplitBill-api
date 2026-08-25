namespace SplitBill.Domain.Entities;

public class User
{
    public long UserId { get; set; }
    public string DisplayName { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public string? AvatarUrl { get; set; }
    public string? PayId { get; set; }
    public string? BankName { get; set; }
    public string? Bsb { get; set; }
    public string? AccountNumber { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
}
