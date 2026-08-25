namespace SplitBill.Application.DTOs;

public record StoreOfferDto(
    string Store,
    string Name,
    decimal? Price,
    string? Unit,
    string? UnitPrice,
    string? Brand,
    string? ProductUrl,
    string? ImageUrl,
    string? ProductId,
    bool InStoreOnly = false,
    string? Note = null);

public record StoreSourceDto(
    string Store,
    bool Ok,
    string? Message = null);

public record ProductCompareResponse(
    string Query,
    IReadOnlyList<StoreOfferDto> Offers,
    IReadOnlyList<StoreSourceDto> Sources);

public record NearestStoreDto(
    string Store,
    string Name,
    string Address,
    double Latitude,
    double Longitude,
    double DistanceKm,
    string MapsUrl);
