using System.Net;
using System.Net.Mail;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
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
        var host = _configuration["Email:Smtp:Host"];
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
        var username = _configuration["Email:Smtp:Username"];
        var password = _configuration["Email:Smtp:Password"];
        var fromAddress = _configuration["Email:FromAddress"] ?? username ?? "noreply@splitbill.local";
        var fromName = _configuration["Email:FromName"] ?? "SplitBill";
        var enableSsl = !string.Equals(
            _configuration["Email:Smtp:EnableSsl"],
            "false",
            StringComparison.OrdinalIgnoreCase);

        using var client = new SmtpClient(host, port)
        {
            EnableSsl = enableSsl,
            DeliveryMethod = SmtpDeliveryMethod.Network,
        };

        if (!string.IsNullOrWhiteSpace(username))
        {
            client.Credentials = new NetworkCredential(username, password);
        }

        using var mail = new MailMessage
        {
            From = new MailAddress(fromAddress, fromName),
            Subject = message.Subject,
            Body = message.HtmlBody,
            IsBodyHtml = true,
        };
        mail.To.Add(message.To);
        mail.AlternateViews.Add(
            AlternateView.CreateAlternateViewFromString(message.TextBody, null, "text/plain"));

        try
        {
            cancellationToken.ThrowIfCancellationRequested();
            await client.SendMailAsync(mail, cancellationToken);
            _logger.LogInformation("Invitation email sent to {To}", message.To);
            return new EmailSendResult(true, "Invitation email sent.");
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to send invitation email to {To}", message.To);
            return new EmailSendResult(false, $"Email send failed: {ex.Message}");
        }
    }
}
