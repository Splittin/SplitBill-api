using SplitBill.Application.DTOs;
using SplitBill.Application.Interfaces;

namespace SplitBill.Application.Services;

public class BillService
{
    private readonly IBillRepository _billRepository;
    private readonly IUserRepository _userRepository;

    public BillService(IBillRepository billRepository, IUserRepository userRepository)
    {
        _billRepository = billRepository;
        _userRepository = userRepository;
    }

    public Task<IReadOnlyList<BillDetailDto>> GetBillsAsync(CancellationToken cancellationToken = default)
        => _billRepository.GetBillsAsync(cancellationToken);

    public Task<IReadOnlyList<BillDetailDto>> GetBillsByGroupAsync(long groupId, CancellationToken cancellationToken = default)
        => _billRepository.GetBillsByGroupAsync(groupId, cancellationToken);

    public Task<BillDetailDto?> GetBillByIdAsync(long billId, CancellationToken cancellationToken = default)
        => _billRepository.GetBillByIdAsync(billId, cancellationToken);

    public async Task<long> CreateBillAsync(CreateBillRequest request, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(request.Title))
        {
            throw new ArgumentException("Title is required.", nameof(request));
        }

        if (request.TotalAmount <= 0)
        {
            throw new ArgumentException("Total amount must be greater than zero.", nameof(request));
        }

        if (request.CreatedByUserId <= 0)
        {
            throw new ArgumentException("CreatedByUserId must be positive.", nameof(request));
        }

        if (request.Participants is null || request.Participants.Count == 0)
        {
            throw new ArgumentException("At least one participant is required.", nameof(request));
        }

        var shareSum = request.Participants.Sum(p => p.ShareAmount);
        if (Math.Abs(shareSum - request.TotalAmount) > 0.01m)
        {
            throw new ArgumentException("Participant shares must equal the bill total.", nameof(request));
        }

        if (request.TaxAmount is < 0 || request.TipAmount is < 0 || request.DiscountAmount is < 0)
        {
            throw new ArgumentException("Tax, tip, and discount cannot be negative.");
        }

        if (request.LineItems is { Count: > 0 })
        {
            foreach (var item in request.LineItems)
            {
                if (string.IsNullOrWhiteSpace(item.Name))
                {
                    throw new ArgumentException("Each line item needs a name.");
                }

                if (item.Quantity <= 0 || item.LineTotal < 0)
                {
                    throw new ArgumentException("Line item quantity/total is invalid.");
                }
            }
        }

        var creator = await _userRepository.GetUserByIdAsync(request.CreatedByUserId, cancellationToken);
        if (creator is null)
        {
            throw new ArgumentException("Bill creator was not found.");
        }

        if (!HasPaymentDetails(creator))
        {
            throw new ArgumentException(
                "Add a PayID or bank account (BSB and account number) in your profile before raising a bill.");
        }

        return await _billRepository.CreateBillAsync(request, cancellationToken);
    }

    private static bool HasPaymentDetails(UserDto user)
    {
        if (!string.IsNullOrWhiteSpace(user.PayId))
        {
            return true;
        }

        return !string.IsNullOrWhiteSpace(user.Bsb) && !string.IsNullOrWhiteSpace(user.AccountNumber);
    }

    public async Task<BillParticipantDto> UpdatePaymentStatusAsync(
        long billId,
        long userId,
        UpdatePaymentStatusRequest request,
        CancellationToken cancellationToken = default)
    {
        if (billId <= 0 || userId <= 0)
        {
            throw new ArgumentException("Bill and user ids must be positive.");
        }

        if (string.IsNullOrWhiteSpace(request.PaymentStatus))
        {
            throw new ArgumentException("Payment status is required.", nameof(request));
        }

        var status = request.PaymentStatus.Trim().ToUpperInvariant();
        if (status is not ("PENDING" or "PAID" or "VERIFY"))
        {
            throw new ArgumentException("Payment status must be PENDING, PAID, or VERIFY.", nameof(request));
        }

        return await _billRepository.UpdatePaymentStatusAsync(billId, userId, status, cancellationToken);
    }
}
