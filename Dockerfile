# SplitBill API — multi-stage build for Linux containers (Railway / Render / Fly)
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

COPY backend/src/SplitBill.Domain/SplitBill.Domain.csproj backend/src/SplitBill.Domain/
COPY backend/src/SplitBill.Application/SplitBill.Application.csproj backend/src/SplitBill.Application/
COPY backend/src/SplitBill.Infrastructure/SplitBill.Infrastructure.csproj backend/src/SplitBill.Infrastructure/
COPY backend/src/SplitBill.Api/SplitBill.Api.csproj backend/src/SplitBill.Api/

RUN dotnet restore backend/src/SplitBill.Api/SplitBill.Api.csproj

COPY backend/src/ backend/src/
RUN dotnet publish backend/src/SplitBill.Api/SplitBill.Api.csproj \
    -c Release \
    -o /app/publish \
    --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS final
WORKDIR /app

# Non-root for security; platforms can still inject PORT
RUN adduser --disabled-password --gecos "" appuser \
    && chown -R appuser /app
USER appuser

COPY --from=build /app/publish .

ENV ASPNETCORE_ENVIRONMENT=Production
ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080

# Prefer platform PORT (Railway/Render) when set
ENTRYPOINT ["sh", "-c", "dotnet SplitBill.Api.dll --urls http://0.0.0.0:${PORT:-8080}"]
