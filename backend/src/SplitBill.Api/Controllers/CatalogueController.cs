using Microsoft.AspNetCore.Mvc;
using SplitBill.Application.DTOs;
using SplitBill.Application.Services;

namespace SplitBill.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class CatalogueController : ControllerBase
{
    private readonly CatalogueService _catalogueService;

    public CatalogueController(CatalogueService catalogueService)
    {
        _catalogueService = catalogueService;
    }

    [HttpGet("compare")]
    public async Task<ActionResult<ProductCompareResponse>> Compare(
        [FromQuery] string q,
        CancellationToken cancellationToken)
    {
        try
        {
            var result = await _catalogueService.CompareAsync(q, cancellationToken);
            return Ok(result);
        }
        catch (ArgumentException ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    [HttpGet("nearest-store")]
    public async Task<ActionResult<NearestStoreDto>> NearestStore(
        [FromQuery] string store,
        [FromQuery] double lat,
        [FromQuery] double lng,
        CancellationToken cancellationToken)
    {
        try
        {
            var nearest = await _catalogueService.FindNearestAsync(store, lat, lng, cancellationToken);
            return nearest is null ? NotFound() : Ok(nearest);
        }
        catch (ArgumentException ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }
}
