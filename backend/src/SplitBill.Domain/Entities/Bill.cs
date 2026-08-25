namespace SplitBill.Domain.Entities;

public class Bill
{
    public long BillId { get; set; }
    public string Title { get; set; } = string.Empty;
    public decimal TotalAmount { get; set; }
    public string CurrencyCode { get; set; } = "USD";
    public long CreatedByUserId { get; set; }
    public DateTime CreatedAt { get; set; }
    public string Status { get; set; } = "OPEN";
}
