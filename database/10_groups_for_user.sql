-- Scope groups to the signed-in user's memberships

CREATE OR REPLACE FUNCTION fn_get_groups_for_user(p_user_id BIGINT)
RETURNS TABLE (
    "GroupId" BIGINT,
    "Name" VARCHAR,
    "CreatedByUserId" BIGINT,
    "CreatedAt" TIMESTAMPTZ,
    "MemberCount" BIGINT,
    "OpenBillCount" BIGINT
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        g.group_id,
        g.name,
        g.created_by_user_id,
        g.created_at,
        (SELECT COUNT(*) FROM group_members gm2 WHERE gm2.group_id = g.group_id),
        (SELECT COUNT(*) FROM bills b WHERE b.group_id = g.group_id AND b.status = 'OPEN')
    FROM groups g
    INNER JOIN group_members gm
        ON gm.group_id = g.group_id
       AND gm.user_id = p_user_id
    ORDER BY g.created_at DESC;
$$;

CREATE OR REPLACE FUNCTION fn_user_is_group_member(p_group_id BIGINT, p_user_id BIGINT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1
          FROM group_members
         WHERE group_id = p_group_id
           AND user_id = p_user_id
    );
$$;
