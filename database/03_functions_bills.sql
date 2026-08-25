-- Bill functions

DROP FUNCTION IF EXISTS fn_create_bill(VARCHAR, NUMERIC, VARCHAR, BIGINT);
DROP FUNCTION IF EXISTS fn_create_bill(VARCHAR, NUMERIC, VARCHAR, BIGINT, BIGINT);
DROP FUNCTION IF EXISTS fn_add_participant(BIGINT, BIGINT, NUMERIC);
DROP FUNCTION IF EXISTS fn_add_participant(BIGINT, BIGINT, NUMERIC, VARCHAR);
DROP FUNCTION IF EXISTS fn_get_bills();
DROP FUNCTION IF EXISTS fn_get_bill_by_id(BIGINT);
DROP FUNCTION IF EXISTS fn_get_bills_by_group(BIGINT);
DROP FUNCTION IF EXISTS fn_get_bill_participants(BIGINT);
DROP FUNCTION IF EXISTS fn_update_participant_payment_status(BIGINT, BIGINT, VARCHAR);

CREATE OR REPLACE FUNCTION fn_create_bill(
    p_title VARCHAR,
    p_total_amount NUMERIC,
    p_currency_code VARCHAR,
    p_created_by BIGINT,
    p_group_id BIGINT DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_bill_id BIGINT;
BEGIN
    INSERT INTO bills (title, total_amount, currency_code, created_by_user_id, group_id)
    VALUES (p_title, p_total_amount, UPPER(p_currency_code), p_created_by, p_group_id)
    RETURNING bill_id INTO v_bill_id;

    RETURN v_bill_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_add_participant(
    p_bill_id BIGINT,
    p_user_id BIGINT,
    p_share_amount NUMERIC,
    p_payment_status VARCHAR DEFAULT 'PENDING'
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO bill_participants (bill_id, user_id, share_amount, payment_status)
    VALUES (p_bill_id, p_user_id, p_share_amount, UPPER(p_payment_status));
END;
$$;

CREATE OR REPLACE FUNCTION fn_get_bills()
RETURNS TABLE (
    "BillId" BIGINT,
    "Title" VARCHAR,
    "TotalAmount" NUMERIC,
    "CurrencyCode" VARCHAR,
    "Status" VARCHAR,
    "CreatedAt" TIMESTAMPTZ,
    "CreatedByUserId" BIGINT,
    "CreatedByDisplayName" VARCHAR,
    "CreatedByPayId" VARCHAR,
    "CreatedByBankName" VARCHAR,
    "CreatedByBsb" VARCHAR,
    "CreatedByAccountNumber" VARCHAR,
    "GroupId" BIGINT,
    "GroupName" VARCHAR
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        b.bill_id,
        b.title,
        b.total_amount,
        b.currency_code,
        b.status,
        b.created_at,
        b.created_by_user_id,
        u.display_name,
        u.pay_id,
        u.bank_name,
        u.bsb,
        u.account_number,
        b.group_id,
        g.name
    FROM bills b
    JOIN app_users u ON u.user_id = b.created_by_user_id
    LEFT JOIN groups g ON g.group_id = b.group_id
    ORDER BY b.created_at DESC;
$$;

CREATE OR REPLACE FUNCTION fn_get_bill_by_id(p_bill_id BIGINT)
RETURNS TABLE (
    "BillId" BIGINT,
    "Title" VARCHAR,
    "TotalAmount" NUMERIC,
    "CurrencyCode" VARCHAR,
    "Status" VARCHAR,
    "CreatedAt" TIMESTAMPTZ,
    "CreatedByUserId" BIGINT,
    "CreatedByDisplayName" VARCHAR,
    "CreatedByPayId" VARCHAR,
    "CreatedByBankName" VARCHAR,
    "CreatedByBsb" VARCHAR,
    "CreatedByAccountNumber" VARCHAR,
    "GroupId" BIGINT,
    "GroupName" VARCHAR
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        b.bill_id,
        b.title,
        b.total_amount,
        b.currency_code,
        b.status,
        b.created_at,
        b.created_by_user_id,
        u.display_name,
        u.pay_id,
        u.bank_name,
        u.bsb,
        u.account_number,
        b.group_id,
        g.name
    FROM bills b
    JOIN app_users u ON u.user_id = b.created_by_user_id
    LEFT JOIN groups g ON g.group_id = b.group_id
    WHERE b.bill_id = p_bill_id;
$$;

CREATE OR REPLACE FUNCTION fn_get_bills_by_group(p_group_id BIGINT)
RETURNS TABLE (
    "BillId" BIGINT,
    "Title" VARCHAR,
    "TotalAmount" NUMERIC,
    "CurrencyCode" VARCHAR,
    "Status" VARCHAR,
    "CreatedAt" TIMESTAMPTZ,
    "CreatedByUserId" BIGINT,
    "CreatedByDisplayName" VARCHAR,
    "CreatedByPayId" VARCHAR,
    "CreatedByBankName" VARCHAR,
    "CreatedByBsb" VARCHAR,
    "CreatedByAccountNumber" VARCHAR,
    "GroupId" BIGINT,
    "GroupName" VARCHAR
)
LANGUAGE sql
STABLE
AS $$
    SELECT *
    FROM fn_get_bills()
    WHERE "GroupId" = p_group_id;
$$;

CREATE OR REPLACE FUNCTION fn_get_bill_participants(p_bill_id BIGINT)
RETURNS TABLE (
    "UserId" BIGINT,
    "DisplayName" VARCHAR,
    "ShareAmount" NUMERIC,
    "PaymentStatus" VARCHAR
)
LANGUAGE sql
STABLE
AS $$
    SELECT bp.user_id, u.display_name, bp.share_amount, bp.payment_status
      FROM bill_participants bp
      JOIN app_users u ON u.user_id = bp.user_id
     WHERE bp.bill_id = p_bill_id
     ORDER BY u.display_name;
$$;

CREATE OR REPLACE FUNCTION fn_update_participant_payment_status(
    p_bill_id BIGINT,
    p_user_id BIGINT,
    p_payment_status VARCHAR
)
RETURNS TABLE (
    "UserId" BIGINT,
    "DisplayName" VARCHAR,
    "ShareAmount" NUMERIC,
    "PaymentStatus" VARCHAR
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_status VARCHAR := UPPER(TRIM(p_payment_status));
    v_all_paid BOOLEAN;
BEGIN
    IF v_status NOT IN ('PENDING', 'PAID', 'VERIFY') THEN
        RAISE EXCEPTION 'Invalid payment status: %', p_payment_status
            USING ERRCODE = '22023';
    END IF;

    UPDATE bill_participants
       SET payment_status = v_status
     WHERE bill_id = p_bill_id
       AND user_id = p_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Participant % not found on bill %', p_user_id, p_bill_id
            USING ERRCODE = 'P0002';
    END IF;

    SELECT NOT EXISTS (
        SELECT 1
          FROM bill_participants
         WHERE bill_id = p_bill_id
           AND payment_status <> 'PAID'
    ) INTO v_all_paid;

    IF v_all_paid THEN
        UPDATE bills
           SET status = 'SETTLED'
         WHERE bill_id = p_bill_id
           AND status = 'OPEN';
    ELSE
        UPDATE bills
           SET status = 'OPEN'
         WHERE bill_id = p_bill_id
           AND status = 'SETTLED';
    END IF;

    RETURN QUERY
        SELECT bp."UserId", bp."DisplayName", bp."ShareAmount", bp."PaymentStatus"
        FROM fn_get_bill_participants(p_bill_id) AS bp
        WHERE bp."UserId" = p_user_id;
END;
$$;
