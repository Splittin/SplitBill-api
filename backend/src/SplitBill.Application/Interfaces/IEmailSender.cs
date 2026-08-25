namespace SplitBill.Application.Interfaces;

public interface IEmailSender
{
    /// <summary>
    /// Sends an email when SMTP is configured; otherwise returns false so callers can surface the invite link.
    /// </summary>
    Task<EmailSendResult> SendAsync(EmailMessage message, CancellationToken cancellationToken = default);
}

public record EmailMessage(
    string To,
    string Subject,
    string HtmlBody,
    string TextBody);

public record EmailSendResult(bool Sent, string? Detail = null);
