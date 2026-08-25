using System.Globalization;
using System.Net.Http.Headers;
using System.Text.Json;
using System.Text.RegularExpressions;
using SplitBill.Application.DTOs;
using SplitBill.Application.Interfaces;

namespace SplitBill.Infrastructure.Services;

public sealed class GroceryPriceService : IGroceryPriceService
{
    private const string BrowserUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36";

    private static readonly string[] SupportedStores =
    [
        "Woolworths", "Coles", "Aldi", "IGA",
        "Target", "Kmart", "Big W",
        "Chemist Warehouse", "Priceline",
        "Tong Li", "Hong Kong Supermarket", "Asian grocery"
    ];

    private readonly HttpClient _httpClient;

    public GroceryPriceService(HttpClient httpClient)
    {
        _httpClient = httpClient;
        _httpClient.DefaultRequestHeaders.UserAgent.Clear();
        _httpClient.DefaultRequestHeaders.UserAgent.ParseAdd(BrowserUserAgent);
        _httpClient.DefaultRequestHeaders.Accept.Clear();
        _httpClient.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("*/*"));
    }

    public async Task<ProductCompareResponse> CompareAsync(string query, CancellationToken cancellationToken = default)
    {
        var wooliesTask = SearchWoolworthsAsync(query, cancellationToken);
        var colesTask = SearchColesAsync(query, cancellationToken);
        var targetTask = SearchTargetAsync(query, cancellationToken);
        var igaTask = SearchIgaAsync(query, cancellationToken);

        await Task.WhenAll(wooliesTask, colesTask, targetTask, igaTask);

        var sources = new List<StoreSourceDto>();
        var offers = new List<StoreOfferDto>();

        void Append((List<StoreOfferDto> Offers, string? Error) result, string store)
        {
            sources.Add(new StoreSourceDto(store, result.Error is null && result.Offers.Count > 0, result.Error));
            offers.AddRange(result.Offers);
        }

        Append(wooliesTask.Result, "Woolworths");
        Append(colesTask.Result, "Coles");
        Append(targetTask.Result, "Target");
        Append(igaTask.Result, "IGA");

        foreach (var specialty in BuildSpecialtyOffers(query))
        {
            sources.Add(new StoreSourceDto(
                specialty.Store,
                specialty.Offers.Count > 0,
                specialty.Message));
            offers.AddRange(specialty.Offers);
        }

        var ranked = offers
            .OrderBy(o => o.Price is null)
            .ThenBy(o => o.Price)
            .ThenBy(o => o.Store)
            .Take(40)
            .ToList();

        return new ProductCompareResponse(query, ranked, sources);
    }

    public async Task<NearestStoreDto?> FindNearestStoreAsync(
        string store,
        double latitude,
        double longitude,
        CancellationToken cancellationToken = default)
    {
        var chain = NormalizeStore(store);
        var delta = 0.08; // ~8–9km box
        var viewbox = string.Create(
            CultureInfo.InvariantCulture,
            $"{longitude - delta},{latitude + delta},{longitude + delta},{latitude - delta}");

        var url =
            "https://nominatim.openstreetmap.org/search" +
            $"?q={Uri.EscapeDataString(chain)}" +
            "&format=json&limit=8&countrycodes=au" +
            $"&viewbox={Uri.EscapeDataString(viewbox)}&bounded=1";

        using var request = new HttpRequestMessage(HttpMethod.Get, url);
        request.Headers.UserAgent.ParseAdd("SplitBill/1.0 (local demo)");
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));

        using var response = await _httpClient.SendAsync(request, cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            return BuildMapsFallback(chain, latitude, longitude);
        }

        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        using var doc = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken);
        if (doc.RootElement.ValueKind != JsonValueKind.Array || doc.RootElement.GetArrayLength() == 0)
        {
            return BuildMapsFallback(chain, latitude, longitude);
        }

        NearestStoreDto? best = null;
        foreach (var item in doc.RootElement.EnumerateArray())
        {
            if (!item.TryGetProperty("lat", out var latProp) || !item.TryGetProperty("lon", out var lonProp))
            {
                continue;
            }

            if (!double.TryParse(latProp.GetString(), NumberStyles.Float, CultureInfo.InvariantCulture, out var lat) ||
                !double.TryParse(lonProp.GetString(), NumberStyles.Float, CultureInfo.InvariantCulture, out var lon))
            {
                continue;
            }

            var distance = HaversineKm(latitude, longitude, lat, lon);
            var name = item.TryGetProperty("name", out var nameProp) ? nameProp.GetString() ?? chain : chain;
            var address = item.TryGetProperty("display_name", out var displayProp)
                ? displayProp.GetString() ?? name
                : name;

            var candidate = new NearestStoreDto(
                chain,
                name,
                address,
                lat,
                lon,
                Math.Round(distance, 2),
                BuildMapsDirectionsUrl(latitude, longitude, lat, lon, name));

            if (best is null || candidate.DistanceKm < best.DistanceKm)
            {
                best = candidate;
            }
        }

        return best ?? BuildMapsFallback(chain, latitude, longitude);
    }

    private async Task<(List<StoreOfferDto> Offers, string? Error)> SearchWoolworthsAsync(
        string query,
        CancellationToken cancellationToken)
    {
        try
        {
            var url =
                "https://www.woolworths.com.au/apis/ui/Search/products" +
                $"?searchTerm={Uri.EscapeDataString(query)}&pageSize=8";

            using var request = new HttpRequestMessage(HttpMethod.Get, url);
            request.Headers.TryAddWithoutValidation("Accept", "application/json");
            request.Headers.TryAddWithoutValidation("Origin", "https://www.woolworths.com.au");
            request.Headers.TryAddWithoutValidation("Referer", "https://www.woolworths.com.au/shop/search/products?searchTerm=" + Uri.EscapeDataString(query));

            using var response = await _httpClient.SendAsync(request, cancellationToken);
            if (!response.IsSuccessStatusCode)
            {
                return ([], $"Woolworths search failed ({(int)response.StatusCode})");
            }

            await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
            using var doc = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken);
            var offers = new List<StoreOfferDto>();

            if (!doc.RootElement.TryGetProperty("Products", out var groups))
            {
                return ([], "Woolworths returned no products");
            }

            foreach (var group in groups.EnumerateArray())
            {
                if (!group.TryGetProperty("Products", out var products))
                {
                    continue;
                }

                foreach (var product in products.EnumerateArray())
                {
                    var stockcode = product.TryGetProperty("Stockcode", out var codeProp)
                        ? codeProp.ToString()
                        : null;
                    if (string.IsNullOrWhiteSpace(stockcode))
                    {
                        continue;
                    }

                    var name = GetString(product, "DisplayName") ?? GetString(product, "Name") ?? "Product";
                    var price = GetDecimal(product, "Price") ?? GetDecimal(product, "InstorePrice");
                    var unit = GetString(product, "PackageSize");
                    var unitPrice = GetString(product, "CupString");
                    var brand = GetString(product, "Brand");
                    var image = GetString(product, "LargeImageFile")
                        ?? GetString(product, "MediumImageFile")
                        ?? GetString(product, "SmallImageFile");
                    image = PreferHttps(image);

                    offers.Add(new StoreOfferDto(
                        "Woolworths",
                        name,
                        price,
                        unit,
                        unitPrice,
                        brand,
                        $"https://www.woolworths.com.au/shop/productdetails/{stockcode}",
                        image,
                        stockcode));
                }
            }

            return (offers.Take(8).ToList(), offers.Count == 0 ? "No Woolworths matches" : null);
        }
        catch (Exception ex)
        {
            return ([], ex.Message);
        }
    }

    private async Task<(List<StoreOfferDto> Offers, string? Error)> SearchTargetAsync(
        string query,
        CancellationToken cancellationToken)
    {
        try
        {
            var url = $"https://www.target.com.au/search?text={Uri.EscapeDataString(query)}";
            using var request = new HttpRequestMessage(HttpMethod.Get, url);
            request.Headers.TryAddWithoutValidation("Accept", "text/html,application/xhtml+xml");
            request.Headers.TryAddWithoutValidation("Referer", "https://www.target.com.au/");

            using var response = await _httpClient.SendAsync(request, cancellationToken);
            if (!response.IsSuccessStatusCode)
            {
                return ([], $"Target search failed ({(int)response.StatusCode})");
            }

            var html = await response.Content.ReadAsStringAsync(cancellationToken);
            var match = Regex.Match(
                html,
                """<script[^>]*id="__NEXT_DATA__"[^>]*>(.*?)</script>""",
                RegexOptions.Singleline | RegexOptions.IgnoreCase);

            if (!match.Success)
            {
                return ([], "Target page data unavailable");
            }

            using var doc = JsonDocument.Parse(match.Groups[1].Value);
            if (!TryGetPropertyPath(
                    doc.RootElement,
                    out var products,
                    "props", "pageProps", "metadata", "productList", "products") ||
                products.ValueKind != JsonValueKind.Array)
            {
                return ([], "Target returned no products");
            }

            var offers = new List<StoreOfferDto>();
            foreach (var product in products.EnumerateArray())
            {
                var id = GetString(product, "id");
                var name = GetString(product, "title") ?? GetString(product, "name");
                if (string.IsNullOrWhiteSpace(name))
                {
                    continue;
                }

                decimal? price = null;
                if (product.TryGetProperty("price", out var pricing))
                {
                    price = GetDecimal(pricing, "offerPrice")
                        ?? GetDecimal(pricing, "recommendedRetailPrice");
                    if (price is null &&
                        pricing.TryGetProperty("priceRange", out var range) &&
                        range.ValueKind == JsonValueKind.Object)
                    {
                        price = GetDecimal(range, "min");
                    }
                }

                var image = PreferHttps(GetString(product, "imageUrl"));
                var productUrl = GetString(product, "baseProductUrl")
                    ?? (id is null ? "https://www.target.com.au/" : $"https://www.target.com.au/p/{id}");

                offers.Add(new StoreOfferDto(
                    "Target",
                    name,
                    price,
                    null,
                    null,
                    "Target",
                    productUrl,
                    image,
                    id));
            }

            return (offers.Take(8).ToList(), offers.Count == 0 ? "No Target matches" : null);
        }
        catch (Exception ex)
        {
            return ([], ex.Message);
        }
    }

    private async Task<(List<StoreOfferDto> Offers, string? Error)> SearchColesAsync(
        string query,
        CancellationToken cancellationToken)
    {
        try
        {
            // Warm cookies / Akamai session from the homepage first.
            using (var warm = new HttpRequestMessage(HttpMethod.Get, "https://www.coles.com.au/"))
            {
                warm.Headers.TryAddWithoutValidation("Accept", "text/html,application/xhtml+xml");
                await _httpClient.SendAsync(warm, cancellationToken);
            }

            var url = $"https://www.coles.com.au/search?q={Uri.EscapeDataString(query)}";
            using var request = new HttpRequestMessage(HttpMethod.Get, url);
            request.Headers.TryAddWithoutValidation("Accept", "text/html,application/xhtml+xml");
            request.Headers.TryAddWithoutValidation("Referer", "https://www.coles.com.au/");
            request.Headers.TryAddWithoutValidation("Origin", "https://www.coles.com.au");

            using var response = await _httpClient.SendAsync(request, cancellationToken);
            if (!response.IsSuccessStatusCode)
            {
                return ([], $"Coles search failed ({(int)response.StatusCode})");
            }

            var html = await response.Content.ReadAsStringAsync(cancellationToken);
            if (html.Contains("Pardon Our Interruption", StringComparison.OrdinalIgnoreCase))
            {
                return ([], "Coles temporarily blocked automated access — try again shortly");
            }

            var match = Regex.Match(
                html,
                """<script[^>]*id="__NEXT_DATA__"[^>]*>(.*?)</script>""",
                RegexOptions.Singleline | RegexOptions.IgnoreCase);

            if (!match.Success)
            {
                return ([], "Coles page data unavailable");
            }

            using var doc = JsonDocument.Parse(match.Groups[1].Value);
            if (!TryGetPropertyPath(
                    doc.RootElement,
                    out var results,
                    "props", "pageProps", "searchResults", "results") ||
                results.ValueKind != JsonValueKind.Array)
            {
                return ([], "Coles returned no products");
            }

            var offers = new List<StoreOfferDto>();
            foreach (var product in results.EnumerateArray())
            {
                var id = product.TryGetProperty("id", out var idProp) ? idProp.ToString() : null;
                var name = GetString(product, "name");
                if (string.IsNullOrWhiteSpace(name))
                {
                    continue;
                }

                decimal? price = null;
                string? unitPrice = null;
                if (product.TryGetProperty("pricing", out var pricing))
                {
                    price = GetDecimal(pricing, "now") ?? GetDecimal(pricing, "rawPriceNow");
                    unitPrice = GetString(pricing, "comparable");
                }

                var brand = GetString(product, "brand");
                var size = GetString(product, "size");
                var image = ExtractColesImage(product, id);
                image = PreferHttps(image);

                offers.Add(new StoreOfferDto(
                    "Coles",
                    string.IsNullOrWhiteSpace(brand) ? name : $"{brand} {name}",
                    price,
                    size,
                    unitPrice,
                    brand,
                    id is null ? "https://www.coles.com.au/" : $"https://www.coles.com.au/product/{id}",
                    image,
                    id));
            }

            return (offers.Take(8).ToList(), offers.Count == 0 ? "No Coles matches" : null);
        }
        catch (Exception ex)
        {
            return ([], ex.Message);
        }
    }

    private async Task<(List<StoreOfferDto> Offers, string? Error)> SearchIgaAsync(
        string query,
        CancellationToken cancellationToken)
    {
        try
        {
            // IGA online search is region-locked; attempt a lightweight HTML probe and
            // surface a store-directions offer if catalogue pricing isn't available.
            var url = $"https://www.igashop.com.au/search?q={Uri.EscapeDataString(query)}";
            using var request = new HttpRequestMessage(HttpMethod.Get, url);
            request.Headers.Accept.Clear();
            request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("text/html"));
            request.Headers.TryAddWithoutValidation(
                "User-Agent",
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36");

            using var response = await _httpClient.SendAsync(request, cancellationToken);
            if (!response.IsSuccessStatusCode)
            {
                return (
                    [
                        new StoreOfferDto(
                            "IGA",
                            $"{ToTitle(query)} (check in store)",
                            null,
                            null,
                            null,
                            "IGA",
                            "https://www.igashop.com.au/",
                            null,
                            "iga-instore",
                            true,
                            "Price depends on your local IGA")
                    ],
                    "IGA online pricing unavailable");
            }

            var html = await response.Content.ReadAsStringAsync(cancellationToken);
            var priced = Regex.Matches(html, @"\$(\d+\.\d{2})")
                .Select(m => m.Groups[1].Value)
                .Distinct()
                .Take(1)
                .ToList();

            // Prefer an in-store directions option — IGA catalogue pages are store-specific.
            return (
                [
                    new StoreOfferDto(
                        "IGA",
                        $"{ToTitle(query)} (local IGA pricing)",
                        priced.Count > 0 && decimal.TryParse(priced[0], NumberStyles.Number, CultureInfo.InvariantCulture, out var p)
                            ? p
                            : null,
                        null,
                        null,
                        "IGA",
                        "https://www.igashop.com.au/",
                        null,
                        "iga-instore",
                        true,
                        "Confirm price at your nearest IGA")
                ],
                null);
        }
        catch (Exception ex)
        {
            return ([], ex.Message);
        }
    }

    private static NearestStoreDto BuildMapsFallback(string store, double latitude, double longitude)
    {
        var mapsUrl =
            "https://www.google.com/maps/dir/?api=1" +
            $"&origin={latitude.ToString(CultureInfo.InvariantCulture)},{longitude.ToString(CultureInfo.InvariantCulture)}" +
            $"&destination={Uri.EscapeDataString(store)}" +
            "&travelmode=driving";

        return new NearestStoreDto(
            store,
            store,
            $"Nearest {store}",
            latitude,
            longitude,
            0,
            mapsUrl);
    }

    private static string BuildMapsDirectionsUrl(
        double originLat,
        double originLng,
        double destLat,
        double destLng,
        string destinationLabel)
    {
        return
            "https://www.google.com/maps/dir/?api=1" +
            $"&origin={originLat.ToString(CultureInfo.InvariantCulture)},{originLng.ToString(CultureInfo.InvariantCulture)}" +
            $"&destination={destLat.ToString(CultureInfo.InvariantCulture)},{destLng.ToString(CultureInfo.InvariantCulture)}" +
            $"&destination_place_id=&travelmode=driving";
    }

    private static string NormalizeStore(string store)
    {
        var trimmed = store.Trim();
        foreach (var known in SupportedStores)
        {
            if (string.Equals(known, trimmed, StringComparison.OrdinalIgnoreCase))
            {
                return known;
            }
        }

        return trimmed;
    }

    private static string ToTitle(string value) =>
        CultureInfo.CurrentCulture.TextInfo.ToTitleCase(value.Trim().ToLowerInvariant());

    private static double HaversineKm(double lat1, double lon1, double lat2, double lon2)
    {
        const double R = 6371;
        var dLat = DegreesToRadians(lat2 - lat1);
        var dLon = DegreesToRadians(lon2 - lon1);
        var a =
            Math.Sin(dLat / 2) * Math.Sin(dLat / 2) +
            Math.Cos(DegreesToRadians(lat1)) * Math.Cos(DegreesToRadians(lat2)) *
            Math.Sin(dLon / 2) * Math.Sin(dLon / 2);
        return R * 2 * Math.Atan2(Math.Sqrt(a), Math.Sqrt(1 - a));
    }

    private static double DegreesToRadians(double degrees) => degrees * Math.PI / 180;

    private static bool TryGetPropertyPath(JsonElement root, out JsonElement value, params string[] path)
    {
        value = root;
        foreach (var segment in path)
        {
            if (value.ValueKind != JsonValueKind.Object || !value.TryGetProperty(segment, out value))
            {
                value = default;
                return false;
            }
        }

        return true;
    }

    private static IReadOnlyList<(string Store, string? Message, List<StoreOfferDto> Offers)> BuildSpecialtyOffers(string query)
    {
        var titled = ToTitle(query);

        StoreOfferDto InStore(string store, string note, string url, string id) =>
            new(
                Store: store,
                Name: $"{titled} (check in store)",
                Price: null,
                Unit: null,
                UnitPrice: null,
                Brand: store,
                ProductUrl: url,
                ImageUrl: null,
                ProductId: id,
                InStoreOnly: true,
                Note: note);

        return
        [
            (
                "Aldi",
                "Aldi doesn't publish a full online grocery catalogue",
                [InStore("Aldi", "Compare specials in store", "https://www.aldi.com.au/", "aldi-instore")]
            ),
            (
                "Kmart",
                "Kmart online search is often blocked — directions available",
                [InStore("Kmart", "Home & everyday essentials", "https://www.kmart.com.au/", "kmart-instore")]
            ),
            (
                "Big W",
                "Big W catalogue is mostly app/store based from this service",
                [InStore("Big W", "General merchandise & pantry", "https://www.bigw.com.au/", "bigw-instore")]
            ),
            (
                "Chemist Warehouse",
                "Pharmacy catalogue is protected — open directions to compare in store",
                [
                    InStore(
                        "Chemist Warehouse",
                        "Pharmacy, vitamins & toiletries",
                        "https://www.chemistwarehouse.com.au/",
                        "cw-instore")
                ]
            ),
            (
                "Priceline",
                "Pharmacy pricing varies by store",
                [
                    InStore(
                        "Priceline",
                        "Pharmacy & beauty",
                        "https://www.priceline.com.au/",
                        "priceline-instore")
                ]
            ),
            (
                "Tong Li",
                "Asian supermarket — confirm price in store",
                [
                    InStore(
                        "Tong Li",
                        "Asian supermarket",
                        "https://www.google.com/maps/search/?api=1&query=Tong+Li+Supermarket",
                        "tongli-instore")
                ]
            ),
            (
                "Hong Kong Supermarket",
                "Asian supermarket — confirm price in store",
                [
                    InStore(
                        "Hong Kong Supermarket",
                        "Asian supermarket",
                        "https://www.google.com/maps/search/?api=1&query=Hong+Kong+Supermarket",
                        "hk-supermarket-instore")
                ]
            ),
            (
                "Asian grocery",
                "Nearby Asian grocers via Maps",
                [
                    InStore(
                        "Asian grocery",
                        "Find nearby Asian markets",
                        "https://www.google.com/maps/search/?api=1&query=Asian+grocery+supermarket",
                        "asian-grocery-instore")
                ]
            ),
        ];
    }

    private static string? ExtractColesImage(JsonElement product, string? id)
    {
        if (product.TryGetProperty("imageUris", out var images) && images.ValueKind == JsonValueKind.Array)
        {
            foreach (var imageNode in images.EnumerateArray())
            {
                var uri = GetString(imageNode, "uri")
                    ?? GetString(imageNode, "url")
                    ?? GetString(imageNode, "src");
                if (!string.IsNullOrWhiteSpace(uri))
                {
                    if (uri.StartsWith("//", StringComparison.Ordinal))
                    {
                        return "https:" + uri;
                    }

                    if (uri.StartsWith('/'))
                    {
                        return "https://www.coles.com.au" + uri;
                    }

                    return uri;
                }
            }
        }

        if (!string.IsNullOrWhiteSpace(id) && id.Length > 0 && id.All(char.IsDigit))
        {
            // Coles CDN convention used by their storefront assets.
            return $"https://cdn.products.coles.com.au/productimages/{id[0]}/{id}.jpg";
        }

        return null;
    }

    private static string? PreferHttps(string? url)
    {
        if (string.IsNullOrWhiteSpace(url))
        {
            return null;
        }

        if (url.StartsWith("//", StringComparison.Ordinal))
        {
            return "https:" + url;
        }

        if (url.StartsWith("http://", StringComparison.OrdinalIgnoreCase))
        {
            return "https://" + url[7..];
        }

        return url;
    }

    private static string? GetString(JsonElement element, string name)
    {
        if (!element.TryGetProperty(name, out var prop))
        {
            return null;
        }

        return prop.ValueKind switch
        {
            JsonValueKind.String => prop.GetString(),
            JsonValueKind.Number => prop.ToString(),
            _ => null
        };
    }

    private static decimal? GetDecimal(JsonElement element, string name)
    {
        if (!element.TryGetProperty(name, out var prop))
        {
            return null;
        }

        return prop.ValueKind switch
        {
            JsonValueKind.Number when prop.TryGetDecimal(out var number) => number,
            JsonValueKind.String when decimal.TryParse(prop.GetString(), NumberStyles.Number, CultureInfo.InvariantCulture, out var parsed)
                => parsed,
            _ => null
        };
    }
}
