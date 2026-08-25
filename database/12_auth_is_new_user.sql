-- Return IsNewUser from auth upsert so clients can run first-time profile setup.
-- Must DROP first: CREATE OR REPLACE cannot change OUT/return columns.

DROP FUNCTION IF EXISTS fn_upsert_auth_user(VARCHAR, VARCHAR, VARCHAR, VARCHAR, TEXT);

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
