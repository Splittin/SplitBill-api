namespace SplitBill.Application.DTOs;

public record BillSummaryDto(
    long BillId,
    string Title,
    decimal TotalAmount,
    string CurrencyCode,
    string Status,
    DateTime CreatedAt,
    long CreatedByUserId,
    string CreatedByDisplayName,
    string? CreatedByPayId,
    string? CreatedByBankName,
    string? CreatedByBsb,
    string? CreatedByAccountNumber,
    long? GroupId,
    string? GroupName);

public record BillDetailDto(
    long BillId,
    string Title,
    decimal TotalAmount,
    string CurrencyCode,
    string Status,
    DateTime CreatedAt,
    long CreatedByUserId,
    string CreatedByDisplayName,
    string? CreatedByPayId,
    string? CreatedByBankName,
    string? CreatedByBsb,
    string? CreatedByAccountNumber,
    long? GroupId,
    string? GroupName,
    IReadOnlyList<BillParticipantDto> Participants);

public record BillParticipantDto(
    long UserId,
    string DisplayName,
    decimal ShareAmount,
    string PaymentStatus);

public record CreateBillRequest(
    string Title,
    decimal TotalAmount,
    string CurrencyCode,
    long CreatedByUserId,
    long? GroupId,
    IReadOnlyList<CreateBillParticipantRequest> Participants,
    decimal? SubtotalAmount = null,
    decimal? TaxAmount = null,
    decimal? TipAmount = null,
    decimal? DiscountAmount = null,
    string? SplitMode = null,
    string? Notes = null,
    IReadOnlyList<CreateBillLineItemRequest>? LineItems = null);

public record CreateBillParticipantRequest(
    long UserId,
    decimal ShareAmount);

public record CreateBillLineItemRequest(
    string Name,
    decimal Quantity,
    decimal UnitPrice,
    decimal LineTotal);

public record ReceiptLineItemDto(
    string Name,
    decimal Quantity,
    decimal UnitPrice,
    decimal LineTotal);

public record ReceiptDraftDto(
    string? Merchant,
    IReadOnlyList<ReceiptLineItemDto> Items,
    decimal? Subtotal,
    decimal? Tax,
    decimal? Tip,
    decimal? Discount,
    decimal? Total,
    string? PaymentMethod,
    string? RawText,
    string? Warning);

public record UpdatePaymentStatusRequest(string PaymentStatus);

public record CreateUserRequest(
    string DisplayName,
    string Email,
    string? PayId = null,
    string? BankName = null,
    string? Bsb = null,
    string? AccountNumber = null,
    string? AvatarUrl = null);

public record UserDto(
    long UserId,
    string DisplayName,
    string Email,
    string? AvatarUrl,
    string? PayId,
    string? BankName,
    string? Bsb,
    string? AccountNumber,
    DateTime CreatedAt,
    DateTime UpdatedAt);

public record UpdateUserProfileRequest(
    string DisplayName,
    string Email,
    string? AvatarUrl,
    string? PayId,
    string? BankName,
    string? Bsb,
    string? AccountNumber);

public record GroupSummaryDto(
    long GroupId,
    string Name,
    long CreatedByUserId,
    DateTime CreatedAt,
    long MemberCount,
    long OpenBillCount);

public record GroupMemberDto(
    long UserId,
    string DisplayName,
    string Email,
    string? AvatarUrl,
    DateTime JoinedAt);

public record GroupDetailDto(
    long GroupId,
    string Name,
    long CreatedByUserId,
    DateTime CreatedAt,
    long MemberCount,
    long OpenBillCount,
    IReadOnlyList<GroupMemberDto> Members);

public record CreateGroupRequest(
    string Name,
    long CreatedByUserId);

public record AddGroupMemberRequest(long UserId);

public record InviteGroupMemberRequest(
    string Email,
    long InvitedByUserId);

public record GroupInviteRecord(
    long InviteId,
    long GroupId,
    string GroupName,
    string Email,
    string Token,
    long InvitedByUserId,
    string InvitedByDisplayName,
    string Status,
    DateTime CreatedAt,
    DateTime ExpiresAt);

public record GroupInviteLookup(
    long InviteId,
    long GroupId,
    string GroupName,
    string Email,
    string Token,
    long InvitedByUserId,
    string InvitedByDisplayName,
    string Status,
    DateTime CreatedAt,
    DateTime ExpiresAt,
    DateTime? AcceptedAt,
    long? AcceptedUserId);

public record GroupInvitePreviewDto(
    string GroupName,
    string Email,
    string InvitedByDisplayName,
    string Status,
    DateTime ExpiresAt);

public record CreateInviteResponse(
    long InviteId,
    string Email,
    string InviteUrl,
    bool EmailSent,
    string? EmailDetail);

public record AcceptInviteResult(
    long GroupId,
    string GroupName,
    long UserId,
    string DisplayName,
    string Email);

public record ShoppingItemDto(
    long ItemId,
    long GroupId,
    string? GroupName,
    string Name,
    bool IsChecked,
    decimal Quantity,
    string? Store,
    decimal? Price,
    string? Brand,
    string? ProductUrl,
    string? ImageUrl,
    string? ProductId,
    string? Unit,
    long AddedByUserId,
    string AddedByDisplayName,
    DateTime CreatedAt);

public record CreateShoppingItemRequest(
    string Name,
    long AddedByUserId,
    decimal Quantity = 1,
    string? Store = null,
    decimal? Price = null,
    string? Brand = null,
    string? ProductUrl = null,
    string? ImageUrl = null,
    string? ProductId = null,
    string? Unit = null);

public record UpdateShoppingItemRequest(
    string? Name = null,
    bool? IsChecked = null,
    decimal? Quantity = null,
    bool SetProduct = false,
    string? Store = null,
    decimal? Price = null,
    string? Brand = null,
    string? ProductUrl = null,
    string? ImageUrl = null,
    string? ProductId = null,
    string? Unit = null);

public record ChatMessageDto(
    long MessageId,
    long GroupId,
    long AuthorUserId,
    string AuthorDisplayName,
    string Body,
    DateTime CreatedAt);

public record CreateChatMessageRequest(
    long AuthorUserId,
    string Body);
