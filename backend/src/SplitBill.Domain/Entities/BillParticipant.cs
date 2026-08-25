namespace SplitBill.Domain.Entities;

public class BillParticipant
{
    public long BillId { get; set; }
    public long UserId { get; set; }
    public string DisplayName { get; set; } = string.Empty;
    public decimal ShareAmount { get; set; }
    public string PaymentStatus { get; set; } = "PENDING";
}
