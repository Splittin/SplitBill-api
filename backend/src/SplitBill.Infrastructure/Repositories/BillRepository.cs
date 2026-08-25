using Dapper;
using Npgsql;
using SplitBill.Application.DTOs;
using SplitBill.Application.Interfaces;

namespace SplitBill.Infrastructure.Repositories;

public class BillRepository : IBillRepository
{
    private readonly IDbConnectionFactory _connectionFactory;

    public BillRepository(IDbConnectionFactory connectionFactory)
    {
        _connectionFactory = connectionFactory;
    }

    public async Task<IReadOnlyList<BillDetailDto>> GetBillsAsync(CancellationToken cancellationToken = default)
    {
        await using var connection = (NpgsqlConnection)await _connectionFactory.CreateOpenConnectionAsync(cancellationToken);

        var rows = await connection.QueryAsync<BillRow>(
            new CommandDefinition(
                "SELECT * FROM fn_get_bills()",
                cancellationToken: cancellationToken));

        return await AttachParticipantsAsync(connection, rows, cancellationToken);
    }

    public async Task<IReadOnlyList<BillDetailDto>> GetBillsByGroupAsync(long groupId, CancellationToken cancellationToken = default)
    {
        await using var connection = (NpgsqlConnection)await _connectionFactory.CreateOpenConnectionAsync(cancellationToken);

        var rows = await connection.QueryAsync<BillRow>(
            new CommandDefinition(
                "SELECT * FROM fn_get_bills_by_group(@GroupId)",
                new { GroupId = groupId },
                cancellationToken: cancellationToken));

        return await AttachParticipantsAsync(connection, rows, cancellationToken);
    }

    public async Task<BillDetailDto?> GetBillByIdAsync(long billId, CancellationToken cancellationToken = default)
    {
        await using var connection = (NpgsqlConnection)await _connectionFactory.CreateOpenConnectionAsync(cancellationToken);

        var row = await connection.QuerySingleOrDefaultAsync<BillRow>(
            new CommandDefinition(
                "SELECT * FROM fn_get_bill_by_id(@BillId)",
                new { BillId = billId },
                cancellationToken: cancellationToken));

        if (row is null)
        {
            return null;
        }

        var participants = await connection.QueryAsync<BillParticipantDto>(
            new CommandDefinition(
                "SELECT * FROM fn_get_bill_participants(@BillId)",
                new { BillId = billId },
                cancellationToken: cancellationToken));

        return ToDetail(row, participants.AsList());
    }

    public async Task<long> CreateBillAsync(CreateBillRequest request, CancellationToken cancellationToken = default)
    {
        await using var connection = (NpgsqlConnection)await _connectionFactory.CreateOpenConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        try
        {
            var billId = await connection.ExecuteScalarAsync<long>(
                new CommandDefinition(
                    """
                    SELECT fn_create_bill(
                        @Title,
                        @TotalAmount,
                        @CurrencyCode,
                        @CreatedByUserId,
                        @GroupId)
                    """,
                    new
                    {
                        request.Title,
                        request.TotalAmount,
                        request.CurrencyCode,
                        request.CreatedByUserId,
                        request.GroupId
                    },
                    transaction,
                    cancellationToken: cancellationToken));

            foreach (var participant in request.Participants)
            {
                var status = participant.UserId == request.CreatedByUserId ? "PAID" : "PENDING";
                await connection.ExecuteAsync(
                    new CommandDefinition(
                        "SELECT fn_add_participant(@BillId, @UserId, @ShareAmount, @PaymentStatus)",
                        new
                        {
                            BillId = billId,
                            participant.UserId,
                            participant.ShareAmount,
                            PaymentStatus = status
                        },
                        transaction,
                        cancellationToken: cancellationToken));
            }

            await connection.ExecuteAsync(
                new CommandDefinition(
                    """
                    SELECT fn_update_bill_extras(
                        @BillId,
                        @Subtotal,
                        @Tax,
                        @Tip,
                        @Discount,
                        @SplitMode,
                        @Notes)
                    """,
                    new
                    {
                        BillId = billId,
                        Subtotal = request.SubtotalAmount,
                        Tax = request.TaxAmount ?? 0m,
                        Tip = request.TipAmount ?? 0m,
                        Discount = request.DiscountAmount ?? 0m,
                        SplitMode = request.SplitMode ?? "TOTAL_EVEN",
                        Notes = request.Notes
                    },
                    transaction,
                    cancellationToken: cancellationToken));

            if (request.LineItems is { Count: > 0 })
            {
                var index = 0;
                foreach (var item in request.LineItems)
                {
                    await connection.ExecuteAsync(
                        new CommandDefinition(
                            """
                            SELECT fn_add_bill_line_item(
                                @BillId,
                                @Position,
                                @Name,
                                @Quantity,
                                @UnitPrice,
                                @LineTotal)
                            """,
                            new
                            {
                                BillId = billId,
                                Position = index++,
                                item.Name,
                                item.Quantity,
                                item.UnitPrice,
                                item.LineTotal
                            },
                            transaction,
                            cancellationToken: cancellationToken));
                }
            }

            await transaction.CommitAsync(cancellationToken);
            return billId;
        }
        catch
        {
            await transaction.RollbackAsync(cancellationToken);
            throw;
        }
    }

    public async Task<BillParticipantDto> UpdatePaymentStatusAsync(
        long billId,
        long userId,
        string paymentStatus,
        CancellationToken cancellationToken = default)
    {
        await using var connection = (NpgsqlConnection)await _connectionFactory.CreateOpenConnectionAsync(cancellationToken);

        try
        {
            var updated = await connection.QuerySingleAsync<BillParticipantDto>(
                new CommandDefinition(
                    "SELECT * FROM fn_update_participant_payment_status(@BillId, @UserId, @PaymentStatus)",
                    new { BillId = billId, UserId = userId, PaymentStatus = paymentStatus },
                    cancellationToken: cancellationToken));

            return updated;
        }
        catch (PostgresException ex) when (ex.SqlState == PostgresErrorCodes.NoDataFound)
        {
            throw new KeyNotFoundException($"Participant {userId} not found on bill {billId}.");
        }
        catch (PostgresException ex) when (ex.SqlState == PostgresErrorCodes.InvalidParameterValue)
        {
            throw new ArgumentException(ex.MessageText);
        }
    }

    private static async Task<IReadOnlyList<BillDetailDto>> AttachParticipantsAsync(
        NpgsqlConnection connection,
        IEnumerable<BillRow> rows,
        CancellationToken cancellationToken)
    {
        var details = new List<BillDetailDto>();
        foreach (var row in rows)
        {
            var participants = await connection.QueryAsync<BillParticipantDto>(
                new CommandDefinition(
                    "SELECT * FROM fn_get_bill_participants(@BillId)",
                    new { BillId = row.BillId },
                    cancellationToken: cancellationToken));
            details.Add(ToDetail(row, participants.AsList()));
        }

        return details;
    }

    private static BillDetailDto ToDetail(BillRow row, IReadOnlyList<BillParticipantDto> participants) =>
        new(
            row.BillId,
            row.Title,
            row.TotalAmount,
            row.CurrencyCode,
            row.Status,
            row.CreatedAt,
            row.CreatedByUserId,
            row.CreatedByDisplayName,
            row.CreatedByPayId,
            row.CreatedByBankName,
            row.CreatedByBsb,
            row.CreatedByAccountNumber,
            row.GroupId,
            row.GroupName,
            participants);

    private sealed class BillRow
    {
        public long BillId { get; init; }
        public string Title { get; init; } = string.Empty;
        public decimal TotalAmount { get; init; }
        public string CurrencyCode { get; init; } = "AUD";
        public string Status { get; init; } = "OPEN";
        public DateTime CreatedAt { get; init; }
        public long CreatedByUserId { get; init; }
        public string CreatedByDisplayName { get; init; } = string.Empty;
        public string? CreatedByPayId { get; init; }
        public string? CreatedByBankName { get; init; }
        public string? CreatedByBsb { get; init; }
        public string? CreatedByAccountNumber { get; init; }
        public long? GroupId { get; init; }
        public string? GroupName { get; init; }
    }
}
