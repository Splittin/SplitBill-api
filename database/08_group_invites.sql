-- Group email invitations

CREATE TABLE IF NOT EXISTS group_invites (
    invite_id          BIGSERIAL PRIMARY KEY,
    group_id           BIGINT       NOT NULL REFERENCES groups (group_id) ON DELETE CASCADE,
    email              VARCHAR(255) NOT NULL,
    token              VARCHAR(64)  NOT NULL,
    invited_by_user_id BIGINT       NOT NULL REFERENCES app_users (user_id),
    status             VARCHAR(20)  NOT NULL DEFAULT 'PENDING',
    created_at         TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    expires_at         TIMESTAMPTZ  NOT NULL,
    accepted_at        TIMESTAMPTZ,
    accepted_user_id   BIGINT       REFERENCES app_users (user_id),
    CONSTRAINT uq_group_invites_token UNIQUE (token),
    CONSTRAINT ck_group_invites_status CHECK (status IN ('PENDING', 'ACCEPTED', 'REVOKED', 'EXPIRED'))
);

CREATE INDEX IF NOT EXISTS ix_group_invites_group ON group_invites (group_id);
CREATE INDEX IF NOT EXISTS ix_group_invites_email ON group_invites (LOWER(email));

CREATE OR REPLACE FUNCTION fn_get_user_by_email(p_email VARCHAR)
RETURNS TABLE (
    "UserId" BIGINT,
    "DisplayName" VARCHAR,
    "Email" VARCHAR,
    "AvatarUrl" TEXT,
    "PayId" VARCHAR,
    "BankName" VARCHAR,
    "Bsb" VARCHAR,
    "AccountNumber" VARCHAR,
    "CreatedAt" TIMESTAMPTZ,
    "UpdatedAt" TIMESTAMPTZ
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        user_id,
        display_name,
        email,
        avatar_url,
        pay_id,
        bank_name,
        bsb,
        account_number,
        created_at,
        updated_at
    FROM app_users
    WHERE email = LOWER(TRIM(p_email));
$$;

CREATE OR REPLACE FUNCTION fn_create_group_invite(
    p_group_id BIGINT,
    p_email VARCHAR,
    p_token VARCHAR,
    p_invited_by BIGINT,
    p_expires_at TIMESTAMPTZ
)
RETURNS TABLE (
    "InviteId" BIGINT,
    "GroupId" BIGINT,
    "GroupName" VARCHAR,
    "Email" VARCHAR,
    "Token" VARCHAR,
    "InvitedByUserId" BIGINT,
    "InvitedByDisplayName" VARCHAR,
    "Status" VARCHAR,
    "CreatedAt" TIMESTAMPTZ,
    "ExpiresAt" TIMESTAMPTZ
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_group_name VARCHAR;
    v_inviter_name VARCHAR;
    v_email VARCHAR := LOWER(TRIM(p_email));
    v_invite_id BIGINT;
    v_existing_user_id BIGINT;
BEGIN
    SELECT name INTO v_group_name
      FROM groups
     WHERE group_id = p_group_id;

    IF v_group_name IS NULL THEN
        RAISE EXCEPTION 'Group % not found', p_group_id
            USING ERRCODE = 'P0002';
    END IF;

    SELECT display_name INTO v_inviter_name
      FROM app_users
     WHERE user_id = p_invited_by;

    IF v_inviter_name IS NULL THEN
        RAISE EXCEPTION 'User % not found', p_invited_by
            USING ERRCODE = 'P0002';
    END IF;

    SELECT user_id INTO v_existing_user_id
      FROM app_users
     WHERE email = v_email;

    IF v_existing_user_id IS NOT NULL
       AND EXISTS (
           SELECT 1 FROM group_members
            WHERE group_id = p_group_id AND user_id = v_existing_user_id
       ) THEN
        RAISE EXCEPTION 'That person is already in this group.'
            USING ERRCODE = 'P0001';
    END IF;

    -- Supersede any pending invites for the same email + group
    UPDATE group_invites
       SET status = 'REVOKED'
     WHERE group_id = p_group_id
       AND email = v_email
       AND status = 'PENDING';

    INSERT INTO group_invites (
        group_id, email, token, invited_by_user_id, expires_at
    )
    VALUES (
        p_group_id, v_email, p_token, p_invited_by, p_expires_at
    )
    RETURNING invite_id INTO v_invite_id;

    RETURN QUERY
        SELECT
            v_invite_id,
            p_group_id,
            v_group_name,
            v_email,
            p_token,
            p_invited_by,
            v_inviter_name,
            'PENDING'::VARCHAR,
            NOW(),
            p_expires_at;
END;
$$;

CREATE OR REPLACE FUNCTION fn_get_group_invite_by_token(p_token VARCHAR)
RETURNS TABLE (
    "InviteId" BIGINT,
    "GroupId" BIGINT,
    "GroupName" VARCHAR,
    "Email" VARCHAR,
    "Token" VARCHAR,
    "InvitedByUserId" BIGINT,
    "InvitedByDisplayName" VARCHAR,
    "Status" VARCHAR,
    "CreatedAt" TIMESTAMPTZ,
    "ExpiresAt" TIMESTAMPTZ,
    "AcceptedAt" TIMESTAMPTZ,
    "AcceptedUserId" BIGINT
)
LANGUAGE plpgsql
AS $$
BEGIN
    -- Expire stale pending invites when looked up
    UPDATE group_invites
       SET status = 'EXPIRED'
     WHERE token = p_token
       AND status = 'PENDING'
       AND expires_at < NOW();

    RETURN QUERY
        SELECT
            i.invite_id,
            i.group_id,
            g.name,
            i.email,
            i.token,
            i.invited_by_user_id,
            u.display_name,
            i.status,
            i.created_at,
            i.expires_at,
            i.accepted_at,
            i.accepted_user_id
        FROM group_invites i
        JOIN groups g ON g.group_id = i.group_id
        JOIN app_users u ON u.user_id = i.invited_by_user_id
        WHERE i.token = p_token;
END;
$$;

CREATE OR REPLACE FUNCTION fn_accept_group_invite(
    p_token VARCHAR,
    p_display_name VARCHAR
)
RETURNS TABLE (
    "GroupId" BIGINT,
    "GroupName" VARCHAR,
    "UserId" BIGINT,
    "DisplayName" VARCHAR,
    "Email" VARCHAR
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_invite group_invites%ROWTYPE;
    v_user_id BIGINT;
    v_display_name VARCHAR := TRIM(p_display_name);
    v_group_name VARCHAR;
BEGIN
    IF v_display_name IS NULL OR LENGTH(v_display_name) = 0 THEN
        RAISE EXCEPTION 'Display name is required.'
            USING ERRCODE = 'P0001';
    END IF;

    UPDATE group_invites
       SET status = 'EXPIRED'
     WHERE token = p_token
       AND status = 'PENDING'
       AND expires_at < NOW();

    SELECT * INTO v_invite
      FROM group_invites
     WHERE token = p_token
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invite not found.'
            USING ERRCODE = 'P0002';
    END IF;

    IF v_invite.status = 'ACCEPTED' THEN
        RAISE EXCEPTION 'This invite was already accepted.'
            USING ERRCODE = 'P0001';
    END IF;

    IF v_invite.status <> 'PENDING' THEN
        RAISE EXCEPTION 'This invite is no longer valid.'
            USING ERRCODE = 'P0001';
    END IF;

    SELECT name INTO v_group_name FROM groups WHERE group_id = v_invite.group_id;

    SELECT user_id INTO v_user_id
      FROM app_users
     WHERE email = v_invite.email;

    IF v_user_id IS NULL THEN
        INSERT INTO app_users (display_name, email)
        VALUES (v_display_name, v_invite.email)
        RETURNING user_id INTO v_user_id;
    ELSE
        UPDATE app_users
           SET display_name = v_display_name,
               updated_at = NOW()
         WHERE user_id = v_user_id
           AND display_name IS DISTINCT FROM v_display_name;
    END IF;

    INSERT INTO group_members (group_id, user_id)
    VALUES (v_invite.group_id, v_user_id)
    ON CONFLICT DO NOTHING;

    UPDATE group_invites
       SET status = 'ACCEPTED',
           accepted_at = NOW(),
           accepted_user_id = v_user_id
     WHERE invite_id = v_invite.invite_id;

    RETURN QUERY
        SELECT
            v_invite.group_id,
            v_group_name,
            v_user_id,
            v_display_name,
            v_invite.email;
END;
$$;
