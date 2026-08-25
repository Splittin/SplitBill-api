using SplitBill.Application.DTOs;
using SplitBill.Application.Interfaces;

namespace SplitBill.Application.Services;

public class ReceiptService
{
    private readonly IReceiptOcrService _ocrService;

    public ReceiptService(IReceiptOcrService ocrService)
    {
        _ocrService = ocrService;
    }

    public Task<ReceiptDraftDto> ParseImageAsync(
        byte[] imageBytes,
        string contentType,
        string? fileName,
        CancellationToken cancellationToken = default)
    {
        if (imageBytes.Length > 12 * 1024 * 1024)
        {
            throw new ArgumentException("Image must be 12MB or smaller.");
        }

        return _ocrService.ParseImageAsync(imageBytes, contentType, fileName, cancellationToken);
    }

    public ReceiptDraftDto ParseText(string rawText)
    {
        if (string.IsNullOrWhiteSpace(rawText))
        {
            throw new ArgumentException("Receipt text is required.");
        }

        return _ocrService.ParseText(rawText);
    }
}
