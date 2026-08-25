-- Auth: Google / email OTP identity + authenticated invite accept

ALTER TABLE app_users
    ADD COLUMN IF NOT EXISTS auth_provider VARCHAR(20) NOT NULL DEFAULT 'email',
    ADD COLUMN IF NOT EXISTS google_sub VARCHAR(255);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_app_users_auth_provider'
    ) THEN
        ALTER TABLE app_users
            ADD CONSTRAINT ck_app_users_auth_provider
            CHECK (auth_provider IN ('email', 'google'));
    END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_app_users_google_sub
    ON app_users (google_sub)
    WHERE google_sub IS NOT NULL;

CREATE TABLE IF NOT EXISTS login_otps (
    otp_id       BIGSERIAL PRIMARY KEY,
    email        VARCHAR(255) NOT NULL,
    code_hash    VARCHAR(128) NOT NULL,
    expires_at   TIMESTAMPTZ  NOT NULL,
    consumed_at  TIMESTAMPTZ,
    attempt_count INT         NOT NULL DEFAULT 0,
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ix_login_otps_email ON login_otps (LOWER(email), created_at DESC);

CREATE OR REPLACE FUNCTION fn_create_login_otp(
    p_email VARCHAR,
    p_code_hash VARCHAR,
    p_expires_at TIMESTAMPTZ
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_email VARCHAR := LOWER(TRIM(p_email));
    v_id BIGINT;
BEGIN
    -- Invalidate outstanding OTPs for this email
    UPDATE login_otps
       SET consumed_at = NOW()
     WHERE email = v_email
       AND consumed_at IS NULL;

    INSERT INTO login_otps (email, code_hash, expires_at)
    VALUES (v_email, p_code_hash, p_expires_at)
    RETURNING otp_id INTO v_id;

    RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_consume_login_otp(
    p_email VARCHAR,
    p_code_hash VARCHAR,
    p_max_attempts INT DEFAULT 5
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_email VARCHAR := LOWER(TRIM(p_email));
    v_otp login_otps%ROWTYPE;
BEGIN
    SELECT * INTO v_otp
      FROM login_otps
     WHERE email = v_email
       AND consumed_at IS NULL
     ORDER BY created_at DESC
     LIMIT 1
     FOR UPDATE;

    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;

    IF v_otp.expires_at < NOW() THEN
        UPDATE login_otps SET consumed_at = NOW() WHERE otp_id = v_otp.otp_id;
        RETURN FALSE;
    END IF;

    IF v_otp.attempt_count >= p_max_attempts THEN
        UPDATE login_otps SET consumed_at = NOW() WHERE otp_id = v_otp.otp_id;
        RETURN FALSE;
    END IF;

    IF v_otp.code_hash IS DISTINCT FROM p_code_hash THEN
        UPDATE login_otps
           SET attempt_count = attempt_count + 1
         WHERE otp_id = v_otp.otp_id;
        RETURN FALSE;
    END IF;

    UPDATE login_otps
       SET consumed_at = NOW()
     WHERE otp_id = v_otp.otp_id;

    RETURN TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION fn_upsert_auth_user(
    p_email VARCHAR,
    p_display_name VARCHAR,
    p_auth_provider VARCHAR,
    p_google_sub VARCHAR DEFAULT NULL,
    p_avatar_url TEXT DEFAULT NULL
)
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
    "UpdatedAt" TIMESTAMPTZ,
    "IsNewUser" BOOLEAN
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_email VARCHAR := LOWER(TRIM(p_email));
    v_name VARCHAR := TRIM(p_display_name);
    v_user_id BIGINT;
    v_is_new BOOLEAN := FALSE;
BEGIN
    IF v_email IS NULL OR LENGTH(v_email) = 0 OR POSITION('@' IN v_email) = 0 THEN
        RAISE EXCEPTION 'A valid email address is required.'
            USING ERRCODE = 'P0001';
    END IF;

    IF v_name IS NULL OR LENGTH(v_name) = 0 THEN
        v_name := SPLIT_PART(v_email, '@', 1);
    END IF;

    IF p_google_sub IS NOT NULL AND LENGTH(TRIM(p_google_sub)) > 0 THEN
        SELECT user_id INTO v_user_id
          FROM app_users
         WHERE google_sub = TRIM(p_google_sub);
    END IF;

    IF v_user_id IS NULL THEN
        SELECT user_id INTO v_user_id
          FROM app_users
         WHERE email = v_email;
    END IF;

    IF v_user_id IS NULL THEN
        INSERT INTO app_users (display_name, email, avatar_url, auth_provider, google_sub)
        VALUES (
            v_name,
            v_email,
            NULLIF(TRIM(p_avatar_url), ''),
            COALESCE(NULLIF(TRIM(p_auth_provider), ''), 'email'),
            NULLIF(TRIM(p_google_sub), '')
        )
        RETURNING user_id INTO v_user_id;
        v_is_new := TRUE;
    ELSE
        UPDATE app_users
           SET avatar_url = COALESCE(NULLIF(TRIM(p_avatar_url), ''), avatar_url),
               auth_provider = COALESCE(NULLIF(TRIM(p_auth_provider), ''), auth_provider),
               google_sub = COALESCE(NULLIF(TRIM(p_google_sub), ''), google_sub),
               updated_at = NOW()
         WHERE user_id = v_user_id;
    END IF;

    RETURN QUERY
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
            updated_at,
            v_is_new
        FROM app_users
        WHERE user_id = v_user_id;
END;
$$;

-- Authenticated accept: join as the logged-in user; email must match invite
CREATE OR REPLACE FUNCTION fn_accept_group_invite_for_user(
    p_token VARCHAR,
    p_user_id BIGINT
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
    v_user app_users%ROWTYPE;
    v_group_name VARCHAR;
BEGIN
    IF p_user_id IS NULL OR p_user_id <= 0 THEN
        RAISE EXCEPTION 'User is required.'
            USING ERRCODE = 'P0001';
    END IF;

    SELECT * INTO v_user
      FROM app_users
     WHERE user_id = p_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'User % not found', p_user_id
            USING ERRCODE = 'P0002';
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

    IF LOWER(v_user.email) <> LOWER(v_invite.email) THEN
        RAISE EXCEPTION 'Sign in with % to accept this invite.', v_invite.email
            USING ERRCODE = 'P0001';
    END IF;

    SELECT name INTO v_group_name FROM groups WHERE group_id = v_invite.group_id;

    INSERT INTO group_members (group_id, user_id)
    VALUES (v_invite.group_id, v_user.user_id)
    ON CONFLICT DO NOTHING;

    UPDATE group_invites
       SET status = 'ACCEPTED',
           accepted_at = NOW(),
           accepted_user_id = v_user.user_id
     WHERE invite_id = v_invite.invite_id;

    RETURN QUERY
        SELECT
            v_invite.group_id,
            v_group_name,
            v_user.user_id,
            v_user.display_name,
            v_user.email;
END;
$$;
