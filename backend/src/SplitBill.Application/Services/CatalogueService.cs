using SplitBill.Application.DTOs;
using SplitBill.Application.Interfaces;

namespace SplitBill.Application.Services;

public class CatalogueService
{
    private readonly IGroceryPriceService _groceryPriceService;

    public CatalogueService(IGroceryPriceService groceryPriceService)
    {
        _groceryPriceService = groceryPriceService;
    }

    public async Task<ProductCompareResponse> CompareAsync(string query, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(query))
        {
            throw new ArgumentException("Search query is required.", nameof(query));
        }

        return await _groceryPriceService.CompareAsync(query.Trim(), cancellationToken);
    }

    public async Task<NearestStoreDto?> FindNearestAsync(
        string store,
        double latitude,
        double longitude,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(store))
        {
            throw new ArgumentException("Store is required.", nameof(store));
        }

        if (latitude is < -90 or > 90 || longitude is < -180 or > 180)
        {
            throw new ArgumentException("Latitude/longitude out of range.");
        }

        return await _groceryPriceService.FindNearestStoreAsync(store.Trim(), latitude, longitude, cancellationToken);
    }
}
