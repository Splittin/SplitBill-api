using Microsoft.AspNetCore.Mvc;
using SplitBill.Application.DTOs;
using SplitBill.Application.Services;

namespace SplitBill.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class BillsController : ControllerBase
{
    private readonly BillService _billService;
    private readonly ReceiptService _receiptService;

    public BillsController(BillService billService, ReceiptService receiptService)
    {
        _billService = billService;
        _receiptService = receiptService;
    }

    [HttpGet]
    public async Task<ActionResult<IReadOnlyList<BillDetailDto>>> GetBills(CancellationToken cancellationToken)
    {
        var bills = await _billService.GetBillsAsync(cancellationToken);
        return Ok(bills);
    }

    [HttpGet("{billId:long}")]
    public async Task<ActionResult<BillDetailDto>> GetBill(long billId, CancellationToken cancellationToken)
    {
        var bill = await _billService.GetBillByIdAsync(billId, cancellationToken);
        return bill is null ? NotFound() : Ok(bill);
    }

    [HttpPost("ocr")]
    [RequestSizeLimit(12 * 1024 * 1024)]
    [Consumes("multipart/form-data")]
    public async Task<ActionResult<ReceiptDraftDto>> OcrReceipt(
        [FromForm] IFormFile? file,
        CancellationToken cancellationToken)
    {
        if (file is null || file.Length == 0)
        {
            return BadRequest(new { error = "Please upload a receipt image." });
        }

        try
        {
            await using var stream = file.OpenReadStream();
            using var ms = new MemoryStream();
            await stream.CopyToAsync(ms, cancellationToken);
            var draft = await _receiptService.ParseImageAsync(
                ms.ToArray(),
                file.ContentType,
                file.FileName,
                cancellationToken);
            return Ok(draft);
        }
        catch (ArgumentException ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    [HttpPost("ocr/text")]
    public ActionResult<ReceiptDraftDto> OcrReceiptText([FromBody] OcrTextRequest request)
    {
        try
        {
            return Ok(_receiptService.ParseText(request.Text ?? string.Empty));
        }
        catch (ArgumentException ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    [HttpPost]
    public async Task<ActionResult<object>> CreateBill([FromBody] CreateBillRequest request, CancellationToken cancellationToken)
    {
        try
        {
            var billId = await _billService.CreateBillAsync(request, cancellationToken);
            return CreatedAtAction(nameof(GetBill), new { billId }, new { billId });
        }
        catch (ArgumentException ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    [HttpPut("{billId:long}/participants/{userId:long}/payment-status")]
    public async Task<ActionResult<BillParticipantDto>> UpdatePaymentStatus(
        long billId,
        long userId,
        [FromBody] UpdatePaymentStatusRequest request,
        CancellationToken cancellationToken)
    {
        try
        {
            var updated = await _billService.UpdatePaymentStatusAsync(billId, userId, request, cancellationToken);
            return Ok(updated);
        }
        catch (ArgumentException ex)
        {
            return BadRequest(new { error = ex.Message });
        }
        catch (KeyNotFoundException)
        {
            return NotFound();
        }
    }
}

public record OcrTextRequest(string Text);
