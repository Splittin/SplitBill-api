-- User profile functions

CREATE OR REPLACE FUNCTION fn_create_user(
    p_display_name VARCHAR,
    p_email VARCHAR,
    p_pay_id VARCHAR DEFAULT NULL,
    p_bank_name VARCHAR DEFAULT NULL,
    p_bsb VARCHAR DEFAULT NULL,
    p_account_number VARCHAR DEFAULT NULL,
    p_avatar_url TEXT DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_user_id BIGINT;
BEGIN
    INSERT INTO app_users (
        display_name,
        email,
        pay_id,
        bank_name,
        bsb,
        account_number,
        avatar_url
    )
    VALUES (
        p_display_name,
        LOWER(p_email),
        p_pay_id,
        p_bank_name,
        p_bsb,
        p_account_number,
        p_avatar_url
    )
    RETURNING user_id INTO v_user_id;

    RETURN v_user_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_get_users()
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
    ORDER BY display_name;
$$;

CREATE OR REPLACE FUNCTION fn_get_user_by_id(p_user_id BIGINT)
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
    WHERE user_id = p_user_id;
$$;

CREATE OR REPLACE FUNCTION fn_update_user_profile(
    p_user_id BIGINT,
    p_display_name VARCHAR,
    p_email VARCHAR,
    p_avatar_url TEXT,
    p_pay_id VARCHAR,
    p_bank_name VARCHAR,
    p_bsb VARCHAR,
    p_account_number VARCHAR
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
    "UpdatedAt" TIMESTAMPTZ
)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE app_users
       SET display_name   = p_display_name,
           email          = LOWER(p_email),
           avatar_url     = NULLIF(TRIM(p_avatar_url), ''),
           pay_id         = NULLIF(TRIM(p_pay_id), ''),
           bank_name      = NULLIF(TRIM(p_bank_name), ''),
           bsb            = NULLIF(TRIM(p_bsb), ''),
           account_number = NULLIF(TRIM(p_account_number), ''),
           updated_at     = NOW()
     WHERE user_id = p_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'User % not found', p_user_id
            USING ERRCODE = 'P0002';
    END IF;

    RETURN QUERY
        SELECT *
        FROM fn_get_user_by_id(p_user_id);
END;
$$;
