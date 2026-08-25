using Microsoft.Extensions.DependencyInjection;
using SplitBill.Application.Services;

namespace SplitBill.Application;

public static class DependencyInjection
{
    public static IServiceCollection AddApplication(this IServiceCollection services)
    {
        services.AddScoped<AuthService>();
        services.AddScoped<BillService>();
        services.AddScoped<GroupService>();
        services.AddScoped<GroupInviteService>();
        services.AddScoped<UserService>();
        services.AddScoped<CatalogueService>();
        services.AddScoped<ReceiptService>();
        return services;
    }
}
