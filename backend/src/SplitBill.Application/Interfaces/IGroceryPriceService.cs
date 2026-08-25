using SplitBill.Application.DTOs;

namespace SplitBill.Application.Interfaces;

public interface IGroceryPriceService
{
    Task<ProductCompareResponse> CompareAsync(string query, CancellationToken cancellationToken = default);
    Task<NearestStoreDto?> FindNearestStoreAsync(
        string store,
        double latitude,
        double longitude,
        CancellationToken cancellationToken = default);
}
