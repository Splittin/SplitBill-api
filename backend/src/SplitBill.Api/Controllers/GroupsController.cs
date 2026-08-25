using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using SplitBill.Application.DTOs;
using SplitBill.Application.Services;

namespace SplitBill.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/[controller]")]
public class GroupsController : ControllerBase
{
    private readonly GroupService _groupService;
    private readonly BillService _billService;
    private readonly GroupInviteService _inviteService;

    public GroupsController(
        GroupService groupService,
        BillService billService,
        GroupInviteService inviteService)
    {
        _groupService = groupService;
        _billService = billService;
        _inviteService = inviteService;
    }

    [HttpGet]
    public async Task<ActionResult<IReadOnlyList<GroupSummaryDto>>> GetGroups(CancellationToken cancellationToken)
    {
        var userId = User.GetUserId();
        if (userId is null)
        {
            return Unauthorized(new { error = "Sign in to view groups." });
        }

        return Ok(await _groupService.GetGroupsForUserAsync(userId.Value, cancellationToken));
    }

    [HttpGet("shopping")]
    public async Task<ActionResult<IReadOnlyList<ShoppingItemDto>>> GetAllShopping(CancellationToken cancellationToken)
    {
        var userId = User.GetUserId();
        if (userId is null)
        {
            return Unauthorized(new { error = "Sign in to view shopping lists." });
        }

        return Ok(await _groupService.GetShoppingItemsForUserAsync(userId.Value, cancellationToken));
    }

    [HttpGet("{groupId:long}")]
    public async Task<ActionResult<GroupDetailDto>> GetGroup(long groupId, CancellationToken cancellationToken)
    {
        var userId = User.GetUserId();
        if (userId is null)
        {
            return Unauthorized(new { error = "Sign in to view this group." });
        }

        if (!await _groupService.IsGroupMemberAsync(groupId, userId.Value, cancellationToken))
        {
            return NotFound();
        }

        var group = await _groupService.GetGroupByIdAsync(groupId, cancellationToken);
        return group is null ? NotFound() : Ok(group);
    }

    [HttpPost]
    public async Task<ActionResult<object>> CreateGroup(
        [FromBody] CreateGroupRequest request,
        CancellationToken cancellationToken)
    {
        var userId = User.GetUserId();
        if (userId is null)
        {
            return Unauthorized(new { error = "Sign in to create a group." });
        }

        try
        {
            var groupId = await _groupService.CreateGroupAsync(userId.Value, request.Name, cancellationToken);
            return CreatedAtAction(nameof(GetGroup), new { groupId }, new { groupId });
        }
        catch (ArgumentException ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    [HttpPost("{groupId:long}/members")]
    public async Task<IActionResult> AddMember(
        long groupId,
        [FromBody] AddGroupMemberRequest request,
        CancellationToken cancellationToken)
    {
        var userId = User.GetUserId();
        if (userId is null || !await _groupService.IsGroupMemberAsync(groupId, userId.Value, cancellationToken))
        {
            return Forbid();
        }

        try
        {
            await _groupService.AddMemberAsync(groupId, request, cancellationToken);
            return NoContent();
        }
        catch (ArgumentException ex)
        {
            return BadRequest(new { error = ex.Message });
        }
        catch (KeyNotFoundException)
        {
            return NotFound();
        }
    }

    [HttpPost("{groupId:long}/invites")]
    public async Task<ActionResult<CreateInviteResponse>> InviteMember(
        long groupId,
        [FromBody] InviteGroupMemberRequest request,
        CancellationToken cancellationToken)
    {
        var userId = User.GetUserId();
        if (userId is null || !await _groupService.IsGroupMemberAsync(groupId, userId.Value, cancellationToken))
        {
            return Forbid();
        }

        try
        {
            var result = await _inviteService.InviteAsync(
                groupId,
                request with { InvitedByUserId = userId.Value },
                cancellationToken);
            return Ok(result);
        }
        catch (ArgumentException ex)
        {
            return BadRequest(new { error = ex.Message });
        }
        catch (KeyNotFoundException)
        {
            return NotFound(new { error = "Group or inviter not found." });
        }
    }

    [HttpDelete("{groupId:long}/members/{memberUserId:long}")]
    public async Task<IActionResult> RemoveMember(long groupId, long memberUserId, CancellationToken cancellationToken)
    {
        var userId = User.GetUserId();
        if (userId is null || !await _groupService.IsGroupMemberAsync(groupId, userId.Value, cancellationToken))
        {
            return Forbid();
        }

        try
        {
            await _groupService.RemoveMemberAsync(groupId, memberUserId, cancellationToken);
            return NoContent();
        }
        catch (ArgumentException ex)
        {
            return BadRequest(new { error = ex.Message });
        }
        catch (KeyNotFoundException)
        {
            return NotFound();
        }
    }

    [HttpGet("{groupId:long}/bills")]
    public async Task<ActionResult<IReadOnlyList<BillDetailDto>>> GetGroupBills(long groupId, CancellationToken cancellationToken)
    {
        var userId = User.GetUserId();
        if (userId is null || !await _groupService.IsGroupMemberAsync(groupId, userId.Value, cancellationToken))
        {
            return NotFound();
        }

        return Ok(await _billService.GetBillsByGroupAsync(groupId, cancellationToken));
    }

    [HttpGet("{groupId:long}/shopping")]
    public async Task<ActionResult<IReadOnlyList<ShoppingItemDto>>> GetShopping(long groupId, CancellationToken cancellationToken)
    {
        var userId = User.GetUserId();
        if (userId is null || !await _groupService.IsGroupMemberAsync(groupId, userId.Value, cancellationToken))
        {
            return NotFound();
        }

        return Ok(await _groupService.GetShoppingItemsAsync(groupId, cancellationToken));
    }

    [HttpPost("{groupId:long}/shopping")]
    public async Task<ActionResult<object>> AddShoppingItem(
        long groupId,
        [FromBody] CreateShoppingItemRequest request,
        CancellationToken cancellationToken)
    {
        var userId = User.GetUserId();
        if (userId is null || !await _groupService.IsGroupMemberAsync(groupId, userId.Value, cancellationToken))
        {
            return Forbid();
        }

        try
        {
            var itemId = await _groupService.AddShoppingItemAsync(
                groupId,
                request with { AddedByUserId = userId.Value },
                cancellationToken);
            return CreatedAtAction(nameof(GetShopping), new { groupId }, new { itemId });
        }
        catch (ArgumentException ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    [HttpPut("shopping/{itemId:long}")]
    public async Task<ActionResult<ShoppingItemDto>> UpdateShoppingItem(
        long itemId,
        [FromBody] UpdateShoppingItemRequest request,
        CancellationToken cancellationToken)
    {
        var auth = await AuthorizeShoppingItemAsync(itemId, cancellationToken);
        if (auth is not null)
        {
            return auth;
        }

        try
        {
            var updated = await _groupService.UpdateShoppingItemAsync(itemId, request, cancellationToken);
            return Ok(updated);
        }
        catch (ArgumentException ex)
        {
            return BadRequest(new { error = ex.Message });
        }
        catch (KeyNotFoundException)
        {
            return NotFound();
        }
    }

    [HttpDelete("shopping/{itemId:long}")]
    public async Task<IActionResult> DeleteShoppingItem(long itemId, CancellationToken cancellationToken)
    {
        var auth = await AuthorizeShoppingItemAsync(itemId, cancellationToken);
        if (auth is not null)
        {
            return auth;
        }

        try
        {
            await _groupService.DeleteShoppingItemAsync(itemId, cancellationToken);
            return NoContent();
        }
        catch (KeyNotFoundException)
        {
            return NotFound();
        }
    }

    [HttpDelete("{groupId:long}/shopping/checked")]
    public async Task<ActionResult<object>> ClearCheckedShoppingItems(long groupId, CancellationToken cancellationToken)
    {
        var userId = User.GetUserId();
        if (userId is null || !await _groupService.IsGroupMemberAsync(groupId, userId.Value, cancellationToken))
        {
            return NotFound();
        }

        var removedCount = await _groupService.ClearCheckedShoppingItemsAsync(groupId, cancellationToken);
        return Ok(new { removedCount });
    }

    [HttpGet("{groupId:long}/messages")]
    public async Task<ActionResult<IReadOnlyList<ChatMessageDto>>> GetMessages(long groupId, CancellationToken cancellationToken)
    {
        var userId = User.GetUserId();
        if (userId is null || !await _groupService.IsGroupMemberAsync(groupId, userId.Value, cancellationToken))
        {
            return NotFound();
        }

        return Ok(await _groupService.GetChatMessagesAsync(groupId, cancellationToken));
    }

    [HttpPost("{groupId:long}/messages")]
    public async Task<ActionResult<object>> AddMessage(
        long groupId,
        [FromBody] CreateChatMessageRequest request,
        CancellationToken cancellationToken)
    {
        var userId = User.GetUserId();
        if (userId is null || !await _groupService.IsGroupMemberAsync(groupId, userId.Value, cancellationToken))
        {
            return Forbid();
        }

        try
        {
            var messageId = await _groupService.AddChatMessageAsync(
                groupId,
                request with { AuthorUserId = userId.Value },
                cancellationToken);
            return CreatedAtAction(nameof(GetMessages), new { groupId }, new { messageId });
        }
        catch (ArgumentException ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    private async Task<ActionResult?> AuthorizeShoppingItemAsync(long itemId, CancellationToken cancellationToken)
    {
        var userId = User.GetUserId();
        if (userId is null)
        {
            return Unauthorized();
        }

        var item = await _groupService.GetShoppingItemAsync(itemId, cancellationToken);
        if (item is null)
        {
            return NotFound();
        }

        if (!await _groupService.IsGroupMemberAsync(item.GroupId, userId.Value, cancellationToken))
        {
            return Forbid();
        }

        return null;
    }
}
