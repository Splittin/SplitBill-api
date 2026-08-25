using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Options;
using SplitBill.Application.DTOs;
using SplitBill.Application.Interfaces;

namespace SplitBill.Application.Services;

public class GroupInviteService
{
    private readonly IGroupInviteRepository _inviteRepository;
    private readonly IEmailSender _emailSender;
    private readonly InviteOptions _options;

    public GroupInviteService(
        IGroupInviteRepository inviteRepository,
        IEmailSender emailSender,
        IOptions<InviteOptions> options)
    {
        _inviteRepository = inviteRepository;
        _emailSender = emailSender;
        _options = options.Value;
    }

    public async Task<CreateInviteResponse> InviteAsync(
        long groupId,
        InviteGroupMemberRequest request,
        CancellationToken cancellationToken = default)
    {
        if (groupId <= 0)
        {
            throw new ArgumentException("Group id must be positive.", nameof(groupId));
        }

        if (request.InvitedByUserId <= 0)
        {
            throw new ArgumentException("InvitedByUserId must be positive.", nameof(request));
        }

        var email = NormalizeEmail(request.Email);
        var token = CreateToken();
        var days = Math.Clamp(_options.InviteExpiryDays <= 0 ? 7 : _options.InviteExpiryDays, 1, 30);
        var expiresAt = DateTime.UtcNow.AddDays(days);

        var invite = await _inviteRepository.CreateInviteAsync(
            groupId,
            email,
            token,
            request.InvitedByUserId,
            expiresAt,
            cancellationToken);

        var inviteUrl = BuildInviteUrl(token);
        var emailResult = await _emailSender.SendAsync(
            BuildInviteEmail(invite, inviteUrl),
            cancellationToken);

        return new CreateInviteResponse(
            invite.InviteId,
            invite.Email,
            inviteUrl,
            emailResult.Sent,
            emailResult.Detail);
    }

    public async Task<GroupInvitePreviewDto> GetPreviewAsync(string token, CancellationToken cancellationToken = default)
    {
        var invite = await RequireInvite(token, cancellationToken);
        return new GroupInvitePreviewDto(
            invite.GroupName,
            invite.Email,
            invite.InvitedByDisplayName,
            invite.Status,
            invite.ExpiresAt);
    }

    public async Task<AcceptInviteResult> AcceptAsync(
        string token,
        long userId,
        CancellationToken cancellationToken = default)
    {
        if (userId <= 0)
        {
            throw new ArgumentException("User id must be positive.", nameof(userId));
        }

        if (string.IsNullOrWhiteSpace(token))
        {
            throw new ArgumentException("Invite token is required.", nameof(token));
        }

        return await _inviteRepository.AcceptForUserAsync(token.Trim(), userId, cancellationToken);
    }

    private async Task<GroupInviteLookup> RequireInvite(string token, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(token))
        {
            throw new ArgumentException("Invite token is required.");
        }

        var invite = await _inviteRepository.GetByTokenAsync(token.Trim(), cancellationToken);
        if (invite is null)
        {
            throw new KeyNotFoundException("Invite not found.");
        }

        return invite;
    }

    private string BuildInviteUrl(string token)
    {
        var baseUrl = (_options.PublicAppBaseUrl ?? "http://localhost:8081").TrimEnd('/');
        return $"{baseUrl}/join/{token}";
    }

    private static EmailMessage BuildInviteEmail(GroupInviteRecord invite, string inviteUrl)
    {
        var subject = $"{invite.InvitedByDisplayName} invited you to {invite.GroupName} on SplitBill";
        var text = new StringBuilder()
            .AppendLine("Hi,")
            .AppendLine()
            .AppendLine($"{invite.InvitedByDisplayName} invited you to join \"{invite.GroupName}\" on SplitBill.")
            .AppendLine()
            .AppendLine("Open this link to join:")
            .AppendLine(inviteUrl)
            .AppendLine()
            .AppendLine($"This invite expires on {invite.ExpiresAt:u} UTC.")
            .ToString();

        var html = $"""
            <p>Hi,</p>
            <p><strong>{System.Net.WebUtility.HtmlEncode(invite.InvitedByDisplayName)}</strong>
               invited you to join <strong>{System.Net.WebUtility.HtmlEncode(invite.GroupName)}</strong> on SplitBill.</p>
            <p><a href="{System.Net.WebUtility.HtmlEncode(inviteUrl)}" style="display:inline-block;padding:12px 18px;background:#1F6B4A;color:#fff;text-decoration:none;border-radius:8px;font-weight:600;">
              Join group
            </a></p>
            <p style="color:#666;font-size:13px;">Or paste this link into your browser:<br/>
              <a href="{System.Net.WebUtility.HtmlEncode(inviteUrl)}">{System.Net.WebUtility.HtmlEncode(inviteUrl)}</a>
            </p>
            <p style="color:#666;font-size:12px;">This invite expires on {invite.ExpiresAt:u} UTC.</p>
            """;

        return new EmailMessage(invite.Email, subject, html, text);
    }

    private static string NormalizeEmail(string email)
    {
        if (string.IsNullOrWhiteSpace(email) || !email.Contains('@', StringComparison.Ordinal))
        {
            throw new ArgumentException("A valid email address is required.");
        }

        return email.Trim().ToLowerInvariant();
    }

    private static string CreateToken()
    {
        Span<byte> bytes = stackalloc byte[24];
        RandomNumberGenerator.Fill(bytes);
        return Convert.ToHexString(bytes).ToLowerInvariant();
    }
}
