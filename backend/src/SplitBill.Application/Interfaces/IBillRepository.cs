using SplitBill.Application.DTOs;

namespace SplitBill.Application.Interfaces;

public interface IBillRepository
{
    Task<IReadOnlyList<BillDetailDto>> GetBillsAsync(CancellationToken cancellationToken = default);
    Task<IReadOnlyList<BillDetailDto>> GetBillsByGroupAsync(long groupId, CancellationToken cancellationToken = default);
    Task<BillDetailDto?> GetBillByIdAsync(long billId, CancellationToken cancellationToken = default);
    Task<long> CreateBillAsync(CreateBillRequest request, CancellationToken cancellationToken = default);
    Task<BillParticipantDto> UpdatePaymentStatusAsync(
        long billId,
        long userId,
        string paymentStatus,
        CancellationToken cancellationToken = default);
}
