using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using SplitBill.Application.DTOs;
using SplitBill.Application.Services;

namespace SplitBill.Api.Controllers;

[ApiController]
[Route("api/invites")]
public class InvitesController : ControllerBase
{
    private readonly GroupInviteService _inviteService;

    public InvitesController(GroupInviteService inviteService)
    {
        _inviteService = inviteService;
    }

    [HttpGet("{token}")]
    [AllowAnonymous]
    public async Task<ActionResult<GroupInvitePreviewDto>> GetInvite(string token, CancellationToken cancellationToken)
    {
        try
        {
            return Ok(await _inviteService.GetPreviewAsync(token, cancellationToken));
        }
        catch (ArgumentException ex)
        {
            return BadRequest(new { error = ex.Message });
        }
        catch (KeyNotFoundException)
        {
            return NotFound(new { error = "Invite not found." });
        }
    }

    [HttpPost("{token}/accept")]
    [Authorize]
    public async Task<ActionResult<AcceptInviteResult>> AcceptInvite(
        string token,
        CancellationToken cancellationToken)
    {
        var userId = User.GetUserId();
        if (userId is null)
        {
            return Unauthorized(new { error = "Sign in to accept this invite." });
        }

        try
        {
            return Ok(await _inviteService.AcceptAsync(token, userId.Value, cancellationToken));
        }
        catch (ArgumentException ex)
        {
            return BadRequest(new { error = ex.Message });
        }
        catch (KeyNotFoundException)
        {
            return NotFound(new { error = "Invite not found." });
        }
    }
}
