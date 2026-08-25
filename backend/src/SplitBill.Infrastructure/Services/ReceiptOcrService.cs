using System.Globalization;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Extensions.Configuration;
using SplitBill.Application.DTOs;
using SplitBill.Application.Interfaces;

namespace SplitBill.Infrastructure.Services;

public sealed class ReceiptOcrService : IReceiptOcrService
{
    private readonly HttpClient _httpClient;
    private readonly string? _apiKey;

    public ReceiptOcrService(HttpClient httpClient, IConfiguration configuration)
    {
        _httpClient = httpClient;
        _apiKey = configuration["Ocr:ApiKey"];
        if (!_httpClient.DefaultRequestHeaders.UserAgent.Any())
        {
            _httpClient.DefaultRequestHeaders.UserAgent.ParseAdd("SplitBill/1.0");
        }
    }

    public async Task<ReceiptDraftDto> ParseImageAsync(
        byte[] imageBytes,
        string contentType,
        string? fileName,
        CancellationToken cancellationToken = default)
    {
        if (imageBytes.Length == 0)
        {
            throw new ArgumentException("Image is empty.");
        }

        string? rawText = null;
        string? warning = null;

        if (string.IsNullOrWhiteSpace(_apiKey))
        {
            warning = "OCR API key is not configured. Enter details manually, or paste receipt text.";
        }
        else
        {
            try
            {
                rawText = await CallOcrSpaceAsync(imageBytes, contentType, fileName, cancellationToken);
            }
            catch (Exception ex)
            {
                warning = $"OCR failed ({ex.Message}). You can edit details manually.";
            }
        }

        if (string.IsNullOrWhiteSpace(rawText))
        {
            return new ReceiptDraftDto(
                null,
                [],
                null,
                null,
                null,
                null,
                null,
                null,
                null,
                warning ?? "Could not read text from this image.");
        }

        var draft = ParseText(rawText);
        return draft with { Warning = warning ?? draft.Warning };
    }

    public ReceiptDraftDto ParseText(string rawText)
    {
        var lines = rawText
            .Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Where(l => l.Length > 1)
            .ToList();

        var merchant = GuessMerchant(lines);
        var total = FindAmount(lines, ["total", "amount due", "balance due", "grand total"]);
        var subtotal = FindAmount(lines, ["subtotal", "sub total", "sub-total"]);
        var tax = FindAmount(lines, ["gst", "tax", "vat"]);
        var tip = FindAmount(lines, ["tip", "gratuity", "service"]);
        var discount = FindAmount(lines, ["discount", "promo", "voucher", "savings"]);
        var payment = GuessPaymentMethod(lines);
        var items = ExtractItems(lines);

        if (total is null && items.Count > 0)
        {
            var itemSum = items.Sum(i => i.LineTotal);
            var extras = (tax ?? 0) + (tip ?? 0) - (discount ?? 0);
            total = itemSum + extras;
            subtotal ??= itemSum;
        }

        string? warning = null;
        if (items.Count == 0 && total is null)
        {
            warning = "Couldn't confidently extract items or total — please fill them in.";
        }

        return new ReceiptDraftDto(
            merchant,
            items,
            subtotal,
            tax,
            tip,
            discount,
            total,
            payment,
            rawText,
            warning);
    }

    private async Task<string> CallOcrSpaceAsync(
        byte[] imageBytes,
        string contentType,
        string? fileName,
        CancellationToken cancellationToken)
    {
        using var form = new MultipartFormDataContent();
                form.Add(new StringContent(_apiKey!), "apikey");
        form.Add(new StringContent("eng"), "language");
        form.Add(new StringContent("true"), "isOverlayRequired");
        form.Add(new StringContent("2"), "OCREngine");

        var fileContent = new ByteArrayContent(imageBytes);
        fileContent.Headers.ContentType = new MediaTypeHeaderValue(
            string.IsNullOrWhiteSpace(contentType) ? "application/octet-stream" : contentType);
        form.Add(fileContent, "file", string.IsNullOrWhiteSpace(fileName) ? "receipt.jpg" : fileName);

        using var response = await _httpClient.PostAsync(
            "https://api.ocr.space/parse/image",
            form,
            cancellationToken);
        var json = await response.Content.ReadAsStringAsync(cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            throw new InvalidOperationException($"OCR HTTP {(int)response.StatusCode}");
        }

        using var doc = JsonDocument.Parse(json);
        if (doc.RootElement.TryGetProperty("IsErroredOnProcessing", out var errored) &&
            errored.ValueKind == JsonValueKind.True)
        {
            var message = doc.RootElement.TryGetProperty("ErrorMessage", out var err)
                ? err.ToString()
                : "OCR processing error";
            throw new InvalidOperationException(message);
        }

        if (!doc.RootElement.TryGetProperty("ParsedResults", out var results) ||
            results.ValueKind != JsonValueKind.Array ||
            results.GetArrayLength() == 0)
        {
            throw new InvalidOperationException("No OCR text returned");
        }

        var text = results[0].TryGetProperty("ParsedText", out var parsed)
            ? parsed.GetString()
            : null;

        if (string.IsNullOrWhiteSpace(text))
        {
            throw new InvalidOperationException("OCR returned empty text");
        }

        return text;
    }

    private static string? GuessMerchant(IReadOnlyList<string> lines)
    {
        foreach (var line in lines.Take(6))
        {
            if (LooksLikeNoise(line) || LooksLikeAmountOnly(line))
            {
                continue;
            }

            if (Regex.IsMatch(line, @"^\d") || line.Contains('@') || line.StartsWith("http", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            return CultureInfo.CurrentCulture.TextInfo.ToTitleCase(line.ToLowerInvariant());
        }

        return null;
    }

    private static string? GuessPaymentMethod(IReadOnlyList<string> lines)
    {
        foreach (var line in lines)
        {
            var lower = line.ToLowerInvariant();
            if (lower.Contains("visa")) return "Visa";
            if (lower.Contains("mastercard") || lower.Contains("master card")) return "Mastercard";
            if (lower.Contains("amex")) return "Amex";
            if (lower.Contains("eftpos")) return "EFTPOS";
            if (lower.Contains("cash")) return "Cash";
            if (lower.Contains("paypal")) return "PayPal";
            if (lower.Contains("apple pay")) return "Apple Pay";
            if (lower.Contains("google pay")) return "Google Pay";
        }

        return null;
    }

    private static decimal? FindAmount(IReadOnlyList<string> lines, IEnumerable<string> keywords)
    {
        foreach (var line in lines)
        {
            var lower = line.ToLowerInvariant();
            if (!keywords.Any(k => lower.Contains(k)))
            {
                continue;
            }

            var match = Regex.Match(line, @"\$?\s*(-?\d+[.,]\d{2})\s*$");
            if (!match.Success)
            {
                match = Regex.Match(line, @"(-?\d+[.,]\d{2})");
            }

            if (match.Success && TryParseMoney(match.Groups[1].Value, out var amount))
            {
                return Math.Abs(amount);
            }
        }

        return null;
    }

    private static List<ReceiptLineItemDto> ExtractItems(IReadOnlyList<string> lines)
    {
        var items = new List<ReceiptLineItemDto>();
        var skip = new[]
        {
            "total", "subtotal", "sub total", "gst", "tax", "tip", "change", "cash", "visa",
            "mastercard", "eftpos", "discount", "loyalty", "abn", "tel", "phone", "www", "http",
            "thank", "welcome", "invoice", "receipt", "table", "server", "qty", "amount"
        };

        foreach (var line in lines)
        {
            var lower = line.ToLowerInvariant();
            if (skip.Any(s => lower.Contains(s)) || LooksLikeNoise(line))
            {
                continue;
            }

            // patterns: "Coffee 2 x 4.50 9.00" or "Pizza 18.00" or "2 MILK 3.50"
            var qtyPrice = Regex.Match(
                line,
                @"^(?<name>.+?)\s+(?<qty>\d+(?:[.,]\d+)?)\s*[xX\*]\s*\$?(?<unit>\d+[.,]\d{2})\s+\$?(?<total>\d+[.,]\d{2})\s*$");
            if (qtyPrice.Success &&
                TryParseMoney(qtyPrice.Groups["unit"].Value, out var unitA) &&
                TryParseMoney(qtyPrice.Groups["total"].Value, out var totalA) &&
                decimal.TryParse(qtyPrice.Groups["qty"].Value.Replace(',', '.'), NumberStyles.Number, CultureInfo.InvariantCulture, out var qtyA))
            {
                items.Add(new ReceiptLineItemDto(CleanName(qtyPrice.Groups["name"].Value), qtyA, unitA, totalA));
                continue;
            }

            var leadingQty = Regex.Match(
                line,
                @"^(?<qty>\d+)\s+(?<name>.+?)\s+\$?(?<total>\d+[.,]\d{2})\s*$");
            if (leadingQty.Success &&
                TryParseMoney(leadingQty.Groups["total"].Value, out var totalB) &&
                decimal.TryParse(leadingQty.Groups["qty"].Value, out var qtyB))
            {
                var unit = qtyB == 0 ? totalB : Math.Round(totalB / qtyB, 2);
                items.Add(new ReceiptLineItemDto(CleanName(leadingQty.Groups["name"].Value), qtyB, unit, totalB));
                continue;
            }

            var simple = Regex.Match(line, @"^(?<name>.+?)\s+\$?(?<total>\d+[.,]\d{2})\s*$");
            if (simple.Success && TryParseMoney(simple.Groups["total"].Value, out var totalC))
            {
                var name = CleanName(simple.Groups["name"].Value);
                if (name.Length < 2 || name.All(char.IsDigit))
                {
                    continue;
                }

                items.Add(new ReceiptLineItemDto(name, 1, totalC, totalC));
            }
        }

        return items.Take(40).ToList();
    }

    private static string CleanName(string value) =>
        Regex.Replace(value, @"\s+", " ").Trim(' ', '-', ':', '.');

    private static bool LooksLikeNoise(string line)
    {
        var lower = line.ToLowerInvariant();
        return lower.Length < 2
               || Regex.IsMatch(line, @"^\W+$")
               || Regex.IsMatch(line, @"^\d{1,2}[:/.-]\d{1,2}")
               || lower.Contains("****");
    }

    private static bool LooksLikeAmountOnly(string line) =>
        Regex.IsMatch(line.Trim(), @"^\$?\s*\d+[.,]\d{2}$");

    private static bool TryParseMoney(string value, out decimal amount) =>
        decimal.TryParse(
            value.Replace("$", "").Replace(",", ".").Trim(),
            NumberStyles.Number,
            CultureInfo.InvariantCulture,
            out amount);
}
