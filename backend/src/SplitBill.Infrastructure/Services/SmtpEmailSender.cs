using MailKit.Net.Smtp;
using MailKit.Security;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using MimeKit;
using SplitBill.Application.Interfaces;

namespace SplitBill.Infrastructure.Services;

public sealed class SmtpEmailSender : IEmailSender
{
    private readonly IConfiguration _configuration;
    private readonly ILogger<SmtpEmailSender> _logger;

    public SmtpEmailSender(IConfiguration configuration, ILogger<SmtpEmailSender> logger)
    {
        _configuration = configuration;
        _logger = logger;
    }

    public async Task<EmailSendResult> SendAsync(EmailMessage message, CancellationToken cancellationToken = default)
    {
        var host = _configuration["Email:Smtp:Host"]?.Trim();
        if (string.IsNullOrWhiteSpace(host))
        {
            _logger.LogInformation(
                "Email SMTP not configured. Invite email to {To} was not sent. Subject: {Subject}",
                message.To,
                message.Subject);
            _logger.LogInformation("Invite email body (text): {Body}", message.TextBody);
            return new EmailSendResult(false, "SMTP is not configured. Share the invite link manually.");
        }

        var port = int.TryParse(_configuration["Email:Smtp:Port"], out var parsedPort) ? parsedPort : 587;
        var username = _configuration["Email:Smtp:Username"]?.Trim();
        // Gmail app passwords are often copied with spaces; strip them.
        var password = (_configuration["Email:Smtp:Password"] ?? string.Empty).Replace(" ", "", StringComparison.Ordinal);
        var fromAddress = (_configuration["Email:FromAddress"] ?? username ?? "noreply@splitbill.local").Trim();
        var fromName = (_configuration["Email:FromName"] ?? "SplitBill").Trim();
        var enableSsl = !string.Equals(
            _configuration["Email:Smtp:EnableSsl"],
            "false",
            StringComparison.OrdinalIgnoreCase);
        var timeoutSeconds = int.TryParse(_configuration["Email:Smtp:TimeoutSeconds"], out var parsedTimeout)
            ? Math.Clamp(parsedTimeout, 5, 120)
            : 20;
        // CRL checks often hang/fail on cloud hosts and some local networks, causing SMTP timeouts.
        var checkRevocation = string.Equals(
            _configuration["Email:Smtp:CheckCertificateRevocation"],
            "true",
            StringComparison.OrdinalIgnoreCase);

        var mime = new MimeMessage();
        mime.From.Add(new MailboxAddress(fromName, fromAddress));
        mime.To.Add(MailboxAddress.Parse(message.To));
        mime.Subject = message.Subject;
        mime.Body = new BodyBuilder
        {
            HtmlBody = message.HtmlBody,
            TextBody = message.TextBody,
        }.ToMessageBody();

        try
        {
            using var client = new SmtpClient
            {
                Timeout = timeoutSeconds * 1000,
                CheckCertificateRevocation = checkRevocation,
            };
            var secureSocket = ResolveSecureSocketOptions(port, enableSsl);

            await client.ConnectAsync(host, port, secureSocket, cancellationToken);

            if (!string.IsNullOrWhiteSpace(username))
            {
                await client.AuthenticateAsync(username, password, cancellationToken);
            }

            await client.SendAsync(mime, cancellationToken);
            await client.DisconnectAsync(true, cancellationToken);

            _logger.LogInformation("Invitation email sent to {To} via {Host}:{Port}", message.To, host, port);
            return new EmailSendResult(true, "Invitation email sent.");
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to send invitation email to {To} via {Host}:{Port}", message.To, host, port);
            return new EmailSendResult(false, $"Email send failed: {ex.Message}");
        }
    }

    private static SecureSocketOptions ResolveSecureSocketOptions(int port, bool enableSsl)
    {
        if (!enableSsl)
        {
            return SecureSocketOptions.None;
        }

        // 465 = implicit SSL; 587 = STARTTLS (Gmail / most providers).
        return port == 465 ? SecureSocketOptions.SslOnConnect : SecureSocketOptions.StartTls;
    }
}
