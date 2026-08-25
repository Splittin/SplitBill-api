using Microsoft.Extensions.DependencyInjection;
using SplitBill.Application.Interfaces;
using SplitBill.Infrastructure.Persistence;
using SplitBill.Infrastructure.Repositories;
using SplitBill.Infrastructure.Services;

namespace SplitBill.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddInfrastructure(this IServiceCollection services)
    {
        services.AddSingleton<IDbConnectionFactory, NpgsqlConnectionFactory>();
        services.AddScoped<IBillRepository, BillRepository>();
        services.AddScoped<IGroupRepository, GroupRepository>();
        services.AddScoped<IGroupInviteRepository, GroupInviteRepository>();
        services.AddScoped<IUserRepository, UserRepository>();
        services.AddScoped<IAuthRepository, AuthRepository>();
        services.AddSingleton<IJwtTokenService, JwtTokenService>();
        services.AddHttpClient(nameof(GoogleTokenValidator));
        services.AddScoped<IGoogleTokenValidator, GoogleTokenValidator>();
        services.AddSingleton<IEmailSender, SmtpEmailSender>();
        services.AddHttpClient<IGroceryPriceService, GroceryPriceService>(client =>
        {
            client.Timeout = TimeSpan.FromSeconds(25);
        })
        .ConfigurePrimaryHttpMessageHandler(() => new HttpClientHandler
        {
            AutomaticDecompression = System.Net.DecompressionMethods.All,
            UseCookies = true,
            CookieContainer = new System.Net.CookieContainer()
        });
        services.AddHttpClient<IReceiptOcrService, ReceiptOcrService>(client =>
        {
            client.Timeout = TimeSpan.FromSeconds(60);
        });
        return services;
    }
}
