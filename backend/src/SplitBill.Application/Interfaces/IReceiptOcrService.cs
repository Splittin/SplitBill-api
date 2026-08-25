using SplitBill.Application.DTOs;

namespace SplitBill.Application.Interfaces;

public interface IReceiptOcrService
{
    Task<ReceiptDraftDto> ParseImageAsync(
        byte[] imageBytes,
        string contentType,
        string? fileName,
        CancellationToken cancellationToken = default);

    ReceiptDraftDto ParseText(string rawText);
}
