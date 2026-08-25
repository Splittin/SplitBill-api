-- SplitBill schema + functions (ported from database/*.sql)
-- Applied in the same order as docker-compose init scripts.


-- ============================================================================ 
-- database/01_schema.sql
-- ============================================================================ 

-- SplitBill PostgreSQL schema

CREATE TABLE IF NOT EXISTS app_users (
    user_id         BIGSERIAL PRIMARY KEY,
    display_name    VARCHAR(100)  NOT NULL,
    email           VARCHAR(255)  NOT NULL,
    avatar_url      TEXT,
    pay_id          VARCHAR(255),
    bank_name       VARCHAR(100),
    bsb             VARCHAR(20),
    account_number  VARCHAR(50),
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_app_users_email UNIQUE (email)
);

CREATE TABLE IF NOT EXISTS groups (
    group_id           BIGSERIAL PRIMARY KEY,
    name               VARCHAR(120) NOT NULL,
    created_by_user_id BIGINT       NOT NULL REFERENCES app_users (user_id),
    created_at         TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS group_members (
    group_id  BIGINT NOT NULL REFERENCES groups (group_id) ON DELETE CASCADE,
    user_id   BIGINT NOT NULL REFERENCES app_users (user_id),
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT pk_group_members PRIMARY KEY (group_id, user_id)
);

CREATE TABLE IF NOT EXISTS bills (
    bill_id            BIGSERIAL PRIMARY KEY,
    title              VARCHAR(200)  NOT NULL,
    total_amount       NUMERIC(12, 2) NOT NULL,
    currency_code      VARCHAR(3)    NOT NULL DEFAULT 'AUD',
    created_by_user_id BIGINT        NOT NULL REFERENCES app_users (user_id),
    group_id           BIGINT        REFERENCES groups (group_id) ON DELETE SET NULL,
    created_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    status             VARCHAR(20)   NOT NULL DEFAULT 'OPEN',
    subtotal_amount    NUMERIC(12, 2),
    tax_amount         NUMERIC(12, 2) NOT NULL DEFAULT 0,
    tip_amount         NUMERIC(12, 2) NOT NULL DEFAULT 0,
    discount_amount    NUMERIC(12, 2) NOT NULL DEFAULT 0,
    split_mode         VARCHAR(40)   NOT NULL DEFAULT 'TOTAL_EVEN',
    notes              TEXT,
    CONSTRAINT ck_bills_status CHECK (status IN ('OPEN', 'SETTLED', 'CANCELLED')),
    CONSTRAINT ck_bills_total CHECK (total_amount > 0)
);

CREATE TABLE IF NOT EXISTS bill_participants (
    bill_id         BIGINT         NOT NULL REFERENCES bills (bill_id) ON DELETE CASCADE,
    user_id         BIGINT         NOT NULL REFERENCES app_users (user_id),
    share_amount    NUMERIC(12, 2) NOT NULL,
    payment_status  VARCHAR(20)    NOT NULL DEFAULT 'PENDING',
    CONSTRAINT pk_bill_participants PRIMARY KEY (bill_id, user_id),
    CONSTRAINT ck_bp_share CHECK (share_amount >= 0),
    CONSTRAINT ck_bp_payment CHECK (payment_status IN ('PENDING', 'PAID', 'VERIFY'))
);

CREATE TABLE IF NOT EXISTS bill_line_items (
    line_item_id    BIGSERIAL PRIMARY KEY,
    bill_id         BIGINT NOT NULL REFERENCES bills (bill_id) ON DELETE CASCADE,
    position_index  INT NOT NULL DEFAULT 0,
    name            VARCHAR(200) NOT NULL,
    quantity        NUMERIC(12, 3) NOT NULL DEFAULT 1,
    unit_price      NUMERIC(12, 2) NOT NULL DEFAULT 0,
    line_total      NUMERIC(12, 2) NOT NULL,
    CONSTRAINT ck_bli_qty CHECK (quantity > 0),
    CONSTRAINT ck_bli_total CHECK (line_total >= 0)
);

CREATE TABLE IF NOT EXISTS shopping_items (
    item_id         BIGSERIAL PRIMARY KEY,
    group_id        BIGINT        NOT NULL REFERENCES groups (group_id) ON DELETE CASCADE,
    name            VARCHAR(200)  NOT NULL,
    is_checked      BOOLEAN       NOT NULL DEFAULT FALSE,
    quantity        NUMERIC(10, 2) NOT NULL DEFAULT 1,
    store           VARCHAR(80),
    price           NUMERIC(12, 2),
    brand           VARCHAR(120),
    product_url     TEXT,
    image_url       TEXT,
    product_id      VARCHAR(120),
    unit            VARCHAR(80),
    added_by_user_id BIGINT       NOT NULL REFERENCES app_users (user_id),
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS chat_messages (
    message_id      BIGSERIAL PRIMARY KEY,
    group_id        BIGINT        NOT NULL REFERENCES groups (group_id) ON DELETE CASCADE,
    author_user_id  BIGINT        NOT NULL REFERENCES app_users (user_id),
    body            TEXT          NOT NULL,
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    CONSTRAINT ck_chat_body CHECK (LENGTH(TRIM(body)) > 0)
);

CREATE INDEX IF NOT EXISTS ix_bills_created_by ON bills (created_by_user_id);
CREATE INDEX IF NOT EXISTS ix_bills_group ON bills (group_id);
CREATE INDEX IF NOT EXISTS ix_bp_user ON bill_participants (user_id);
CREATE INDEX IF NOT EXISTS ix_bli_bill ON bill_line_items (bill_id);
CREATE INDEX IF NOT EXISTS ix_group_members_user ON group_members (user_id);
CREATE INDEX IF NOT EXISTS ix_shopping_group ON shopping_items (group_id);
CREATE INDEX IF NOT EXISTS ix_chat_group ON chat_messages (group_id, created_at);


-- ============================================================================ 
-- database/02_functions_users.sql
-- ============================================================================ 

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


-- ============================================================================ 
-- database/03_functions_bills.sql
-- ============================================================================ 

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


-- ============================================================================ 
-- database/04_functions_groups.sql
-- ============================================================================ 

-- Group, shopping, and chat functions

CREATE OR REPLACE FUNCTION fn_create_group(
    p_name VARCHAR,
    p_created_by BIGINT
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_group_id BIGINT;
BEGIN
    INSERT INTO groups (name, created_by_user_id)
    VALUES (TRIM(p_name), p_created_by)
    RETURNING group_id INTO v_group_id;

    INSERT INTO group_members (group_id, user_id)
    VALUES (v_group_id, p_created_by);

    RETURN v_group_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_add_group_member(
    p_group_id BIGINT,
    p_user_id BIGINT
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM groups WHERE group_id = p_group_id) THEN
        RAISE EXCEPTION 'Group % not found', p_group_id
            USING ERRCODE = 'P0002';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM app_users WHERE user_id = p_user_id) THEN
        RAISE EXCEPTION 'User % not found', p_user_id
            USING ERRCODE = 'P0002';
    END IF;

    INSERT INTO group_members (group_id, user_id)
    VALUES (p_group_id, p_user_id)
    ON CONFLICT DO NOTHING;
END;
$$;

CREATE OR REPLACE FUNCTION fn_remove_group_member(
    p_group_id BIGINT,
    p_user_id BIGINT
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    DELETE FROM group_members
     WHERE group_id = p_group_id
       AND user_id = p_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Member % not found in group %', p_user_id, p_group_id
            USING ERRCODE = 'P0002';
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION fn_get_groups()
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
        (SELECT COUNT(*) FROM group_members gm WHERE gm.group_id = g.group_id),
        (SELECT COUNT(*) FROM bills b WHERE b.group_id = g.group_id AND b.status = 'OPEN')
    FROM groups g
    ORDER BY g.created_at DESC;
$$;

CREATE OR REPLACE FUNCTION fn_get_group_by_id(p_group_id BIGINT)
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
    SELECT *
    FROM fn_get_groups()
    WHERE "GroupId" = p_group_id;
$$;

CREATE OR REPLACE FUNCTION fn_get_group_members(p_group_id BIGINT)
RETURNS TABLE (
    "UserId" BIGINT,
    "DisplayName" VARCHAR,
    "Email" VARCHAR,
    "AvatarUrl" TEXT,
    "JoinedAt" TIMESTAMPTZ
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        u.user_id,
        u.display_name,
        u.email,
        u.avatar_url,
        gm.joined_at
    FROM group_members gm
    JOIN app_users u ON u.user_id = gm.user_id
    WHERE gm.group_id = p_group_id
    ORDER BY u.display_name;
$$;

CREATE OR REPLACE FUNCTION fn_add_shopping_item(
    p_group_id BIGINT,
    p_name VARCHAR,
    p_added_by BIGINT,
    p_quantity NUMERIC DEFAULT 1,
    p_store VARCHAR DEFAULT NULL,
    p_price NUMERIC DEFAULT NULL,
    p_brand VARCHAR DEFAULT NULL,
    p_product_url TEXT DEFAULT NULL,
    p_image_url TEXT DEFAULT NULL,
    p_product_id VARCHAR DEFAULT NULL,
    p_unit VARCHAR DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_item_id BIGINT;
    v_qty NUMERIC := COALESCE(NULLIF(p_quantity, 0), 1);
BEGIN
    IF v_qty < 0 THEN
        RAISE EXCEPTION 'Quantity must be zero or greater'
            USING ERRCODE = '22023';
    END IF;

    INSERT INTO shopping_items (
        group_id, name, added_by_user_id, quantity,
        store, price, brand, product_url, image_url, product_id, unit
    )
    VALUES (
        p_group_id,
        TRIM(p_name),
        p_added_by,
        v_qty,
        NULLIF(TRIM(p_store), ''),
        p_price,
        NULLIF(TRIM(p_brand), ''),
        NULLIF(TRIM(p_product_url), ''),
        NULLIF(TRIM(p_image_url), ''),
        NULLIF(TRIM(p_product_id), ''),
        NULLIF(TRIM(p_unit), '')
    )
    RETURNING item_id INTO v_item_id;

    RETURN v_item_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_get_shopping_item(p_item_id BIGINT)
RETURNS TABLE (
    "ItemId" BIGINT,
    "GroupId" BIGINT,
    "Name" VARCHAR,
    "IsChecked" BOOLEAN,
    "Quantity" NUMERIC,
    "Store" VARCHAR,
    "Price" NUMERIC,
    "Brand" VARCHAR,
    "ProductUrl" TEXT,
    "ImageUrl" TEXT,
    "ProductId" VARCHAR,
    "Unit" VARCHAR,
    "AddedByUserId" BIGINT,
    "AddedByDisplayName" VARCHAR,
    "CreatedAt" TIMESTAMPTZ
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        s.item_id,
        s.group_id,
        s.name,
        s.is_checked,
        s.quantity,
        s.store,
        s.price,
        s.brand,
        s.product_url,
        s.image_url,
        s.product_id,
        s.unit,
        s.added_by_user_id,
        u.display_name,
        s.created_at
    FROM shopping_items s
    JOIN app_users u ON u.user_id = s.added_by_user_id
    WHERE s.item_id = p_item_id;
$$;

CREATE OR REPLACE FUNCTION fn_get_shopping_items(p_group_id BIGINT)
RETURNS TABLE (
    "ItemId" BIGINT,
    "GroupId" BIGINT,
    "Name" VARCHAR,
    "IsChecked" BOOLEAN,
    "Quantity" NUMERIC,
    "Store" VARCHAR,
    "Price" NUMERIC,
    "Brand" VARCHAR,
    "ProductUrl" TEXT,
    "ImageUrl" TEXT,
    "ProductId" VARCHAR,
    "Unit" VARCHAR,
    "AddedByUserId" BIGINT,
    "AddedByDisplayName" VARCHAR,
    "CreatedAt" TIMESTAMPTZ
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        s.item_id,
        s.group_id,
        s.name,
        s.is_checked,
        s.quantity,
        s.store,
        s.price,
        s.brand,
        s.product_url,
        s.image_url,
        s.product_id,
        s.unit,
        s.added_by_user_id,
        u.display_name,
        s.created_at
    FROM shopping_items s
    JOIN app_users u ON u.user_id = s.added_by_user_id
    WHERE s.group_id = p_group_id
    ORDER BY s.is_checked, s.created_at DESC;
$$;

CREATE OR REPLACE FUNCTION fn_update_shopping_item(
    p_item_id BIGINT,
    p_name VARCHAR DEFAULT NULL,
    p_is_checked BOOLEAN DEFAULT NULL,
    p_quantity NUMERIC DEFAULT NULL,
    p_set_product BOOLEAN DEFAULT FALSE,
    p_store VARCHAR DEFAULT NULL,
    p_price NUMERIC DEFAULT NULL,
    p_brand VARCHAR DEFAULT NULL,
    p_product_url TEXT DEFAULT NULL,
    p_image_url TEXT DEFAULT NULL,
    p_product_id VARCHAR DEFAULT NULL,
    p_unit VARCHAR DEFAULT NULL
)
RETURNS TABLE (
    "ItemId" BIGINT,
    "GroupId" BIGINT,
    "Name" VARCHAR,
    "IsChecked" BOOLEAN,
    "Quantity" NUMERIC,
    "Store" VARCHAR,
    "Price" NUMERIC,
    "Brand" VARCHAR,
    "ProductUrl" TEXT,
    "ImageUrl" TEXT,
    "ProductId" VARCHAR,
    "Unit" VARCHAR,
    "AddedByUserId" BIGINT,
    "AddedByDisplayName" VARCHAR,
    "CreatedAt" TIMESTAMPTZ
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_name IS NULL
       AND p_is_checked IS NULL
       AND p_quantity IS NULL
       AND NOT COALESCE(p_set_product, FALSE) THEN
        RAISE EXCEPTION 'At least one field is required to update a shopping item'
            USING ERRCODE = '22023';
    END IF;

    IF p_name IS NOT NULL AND LENGTH(TRIM(p_name)) = 0 THEN
        RAISE EXCEPTION 'Item name cannot be empty'
            USING ERRCODE = '22023';
    END IF;

    IF p_quantity IS NOT NULL AND p_quantity < 0 THEN
        RAISE EXCEPTION 'Quantity must be zero or greater'
            USING ERRCODE = '22023';
    END IF;

    UPDATE shopping_items
       SET name = CASE WHEN p_name IS NULL THEN name ELSE TRIM(p_name) END,
           is_checked = COALESCE(p_is_checked, is_checked),
           quantity = COALESCE(p_quantity, quantity),
           store = CASE WHEN COALESCE(p_set_product, FALSE) THEN NULLIF(TRIM(p_store), '') ELSE store END,
           price = CASE WHEN COALESCE(p_set_product, FALSE) THEN p_price ELSE price END,
           brand = CASE WHEN COALESCE(p_set_product, FALSE) THEN NULLIF(TRIM(p_brand), '') ELSE brand END,
           product_url = CASE WHEN COALESCE(p_set_product, FALSE) THEN NULLIF(TRIM(p_product_url), '') ELSE product_url END,
           image_url = CASE WHEN COALESCE(p_set_product, FALSE) THEN NULLIF(TRIM(p_image_url), '') ELSE image_url END,
           product_id = CASE WHEN COALESCE(p_set_product, FALSE) THEN NULLIF(TRIM(p_product_id), '') ELSE product_id END,
           unit = CASE WHEN COALESCE(p_set_product, FALSE) THEN NULLIF(TRIM(p_unit), '') ELSE unit END
     WHERE item_id = p_item_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Shopping item % not found', p_item_id
            USING ERRCODE = 'P0002';
    END IF;

    RETURN QUERY
        SELECT *
        FROM fn_get_shopping_item(p_item_id);
END;
$$;

CREATE OR REPLACE FUNCTION fn_set_shopping_item_checked(
    p_item_id BIGINT,
    p_is_checked BOOLEAN
)
RETURNS TABLE (
    "ItemId" BIGINT,
    "GroupId" BIGINT,
    "Name" VARCHAR,
    "IsChecked" BOOLEAN,
    "Quantity" NUMERIC,
    "Store" VARCHAR,
    "Price" NUMERIC,
    "Brand" VARCHAR,
    "ProductUrl" TEXT,
    "ImageUrl" TEXT,
    "ProductId" VARCHAR,
    "Unit" VARCHAR,
    "AddedByUserId" BIGINT,
    "AddedByDisplayName" VARCHAR,
    "CreatedAt" TIMESTAMPTZ
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
        SELECT *
        FROM fn_update_shopping_item(p_item_id, NULL, p_is_checked);
END;
$$;

CREATE OR REPLACE FUNCTION fn_delete_shopping_item(p_item_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    DELETE FROM shopping_items
     WHERE item_id = p_item_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Shopping item % not found', p_item_id
            USING ERRCODE = 'P0002';
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION fn_clear_checked_shopping_items(p_group_id BIGINT)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_removed BIGINT;
BEGIN
    DELETE FROM shopping_items
     WHERE group_id = p_group_id
       AND is_checked = TRUE;

    GET DIAGNOSTICS v_removed = ROW_COUNT;
    RETURN v_removed;
END;
$$;

CREATE OR REPLACE FUNCTION fn_add_chat_message(
    p_group_id BIGINT,
    p_author_user_id BIGINT,
    p_body TEXT
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_message_id BIGINT;
BEGIN
    INSERT INTO chat_messages (group_id, author_user_id, body)
    VALUES (p_group_id, p_author_user_id, TRIM(p_body))
    RETURNING message_id INTO v_message_id;

    RETURN v_message_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_get_chat_messages(p_group_id BIGINT)
RETURNS TABLE (
    "MessageId" BIGINT,
    "GroupId" BIGINT,
    "AuthorUserId" BIGINT,
    "AuthorDisplayName" VARCHAR,
    "Body" TEXT,
    "CreatedAt" TIMESTAMPTZ
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        m.message_id,
        m.group_id,
        m.author_user_id,
        u.display_name,
        m.body,
        m.created_at
    FROM chat_messages m
    JOIN app_users u ON u.user_id = m.author_user_id
    WHERE m.group_id = p_group_id
    ORDER BY m.created_at ASC, m.message_id ASC;
$$;


-- ============================================================================ 
-- database/07_bill_line_items.sql
-- ============================================================================ 

-- Bill line items + helper for receipt-backed bills

ALTER TABLE bills
    ADD COLUMN IF NOT EXISTS subtotal_amount NUMERIC(12, 2),
    ADD COLUMN IF NOT EXISTS tax_amount NUMERIC(12, 2) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS tip_amount NUMERIC(12, 2) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS discount_amount NUMERIC(12, 2) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS split_mode VARCHAR(40) NOT NULL DEFAULT 'TOTAL_EVEN',
    ADD COLUMN IF NOT EXISTS notes TEXT;

CREATE TABLE IF NOT EXISTS bill_line_items (
    line_item_id    BIGSERIAL PRIMARY KEY,
    bill_id         BIGINT NOT NULL REFERENCES bills (bill_id) ON DELETE CASCADE,
    position_index  INT NOT NULL DEFAULT 0,
    name            VARCHAR(200) NOT NULL,
    quantity        NUMERIC(12, 3) NOT NULL DEFAULT 1,
    unit_price      NUMERIC(12, 2) NOT NULL DEFAULT 0,
    line_total      NUMERIC(12, 2) NOT NULL,
    CONSTRAINT ck_bli_qty CHECK (quantity > 0),
    CONSTRAINT ck_bli_total CHECK (line_total >= 0)
);

CREATE INDEX IF NOT EXISTS ix_bli_bill ON bill_line_items (bill_id);

CREATE OR REPLACE FUNCTION fn_add_bill_line_item(
    p_bill_id BIGINT,
    p_position INT,
    p_name VARCHAR,
    p_quantity NUMERIC,
    p_unit_price NUMERIC,
    p_line_total NUMERIC
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_id BIGINT;
BEGIN
    INSERT INTO bill_line_items (bill_id, position_index, name, quantity, unit_price, line_total)
    VALUES (p_bill_id, p_position, TRIM(p_name), p_quantity, p_unit_price, p_line_total)
    RETURNING line_item_id INTO v_id;

    RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_update_bill_extras(
    p_bill_id BIGINT,
    p_subtotal NUMERIC,
    p_tax NUMERIC,
    p_tip NUMERIC,
    p_discount NUMERIC,
    p_split_mode VARCHAR,
    p_notes TEXT
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE bills
       SET subtotal_amount = p_subtotal,
           tax_amount = COALESCE(p_tax, 0),
           tip_amount = COALESCE(p_tip, 0),
           discount_amount = COALESCE(p_discount, 0),
           split_mode = COALESCE(NULLIF(TRIM(p_split_mode), ''), 'TOTAL_EVEN'),
           notes = NULLIF(TRIM(p_notes), '')
     WHERE bill_id = p_bill_id;
END;
$$;


-- ============================================================================ 
-- database/08_group_invites.sql
-- ============================================================================ 

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


-- ============================================================================ 
-- database/09_auth.sql
-- ============================================================================ 

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


-- ============================================================================ 
-- database/10_groups_for_user.sql
-- ============================================================================ 

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


-- ============================================================================ 
-- database/11_shopping_item_crud.sql
-- ============================================================================ 

-- Shopping item edit, delete, and clear-checked helpers (run on existing databases)

CREATE OR REPLACE FUNCTION fn_update_shopping_item(
    p_item_id BIGINT,
    p_name VARCHAR DEFAULT NULL,
    p_is_checked BOOLEAN DEFAULT NULL
)
RETURNS TABLE (
    "ItemId" BIGINT,
    "GroupId" BIGINT,
    "Name" VARCHAR,
    "IsChecked" BOOLEAN,
    "AddedByUserId" BIGINT,
    "AddedByDisplayName" VARCHAR,
    "CreatedAt" TIMESTAMPTZ
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_name IS NULL AND p_is_checked IS NULL THEN
        RAISE EXCEPTION 'At least one field is required to update a shopping item'
            USING ERRCODE = '22023';
    END IF;

    IF p_name IS NOT NULL AND LENGTH(TRIM(p_name)) = 0 THEN
        RAISE EXCEPTION 'Item name cannot be empty'
            USING ERRCODE = '22023';
    END IF;

    UPDATE shopping_items
       SET name = CASE WHEN p_name IS NULL THEN name ELSE TRIM(p_name) END,
           is_checked = COALESCE(p_is_checked, is_checked)
     WHERE item_id = p_item_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Shopping item % not found', p_item_id
            USING ERRCODE = 'P0002';
    END IF;

    RETURN QUERY
        SELECT *
        FROM fn_get_shopping_item(p_item_id);
END;
$$;

CREATE OR REPLACE FUNCTION fn_delete_shopping_item(p_item_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    DELETE FROM shopping_items
     WHERE item_id = p_item_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Shopping item % not found', p_item_id
            USING ERRCODE = 'P0002';
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION fn_clear_checked_shopping_items(p_group_id BIGINT)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_removed BIGINT;
BEGIN
    DELETE FROM shopping_items
     WHERE group_id = p_group_id
       AND is_checked = TRUE;

    GET DIAGNOSTICS v_removed = ROW_COUNT;
    RETURN v_removed;
END;
$$;


-- ============================================================================ 
-- database/12_auth_is_new_user.sql
-- ============================================================================ 

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


-- ============================================================================ 
-- database/13_shopping_product_details.sql
-- ============================================================================ 

-- Shopping list: quantity + selected product/store details
-- Run on existing DBs. Fresh installs also get this via docker-compose.

ALTER TABLE shopping_items
    ADD COLUMN IF NOT EXISTS quantity NUMERIC(10, 2) NOT NULL DEFAULT 1,
    ADD COLUMN IF NOT EXISTS store VARCHAR(80),
    ADD COLUMN IF NOT EXISTS price NUMERIC(12, 2),
    ADD COLUMN IF NOT EXISTS brand VARCHAR(120),
    ADD COLUMN IF NOT EXISTS product_url TEXT,
    ADD COLUMN IF NOT EXISTS image_url TEXT,
    ADD COLUMN IF NOT EXISTS product_id VARCHAR(120),
    ADD COLUMN IF NOT EXISTS unit VARCHAR(80);

-- Return type / signatures change → drop then recreate
DROP FUNCTION IF EXISTS fn_get_shopping_item(BIGINT);
DROP FUNCTION IF EXISTS fn_get_shopping_items(BIGINT);
DROP FUNCTION IF EXISTS fn_add_shopping_item(BIGINT, VARCHAR, BIGINT);
DROP FUNCTION IF EXISTS fn_add_shopping_item(BIGINT, VARCHAR, BIGINT, NUMERIC, VARCHAR, NUMERIC, VARCHAR, TEXT, TEXT, VARCHAR, VARCHAR);
DROP FUNCTION IF EXISTS fn_update_shopping_item(BIGINT, VARCHAR, BOOLEAN);
DROP FUNCTION IF EXISTS fn_update_shopping_item(BIGINT, VARCHAR, BOOLEAN, NUMERIC, BOOLEAN, VARCHAR, NUMERIC, VARCHAR, TEXT, TEXT, VARCHAR, VARCHAR);
DROP FUNCTION IF EXISTS fn_set_shopping_item_checked(BIGINT, BOOLEAN);

CREATE OR REPLACE FUNCTION fn_get_shopping_item(p_item_id BIGINT)
RETURNS TABLE (
    "ItemId" BIGINT,
    "GroupId" BIGINT,
    "GroupName" VARCHAR,
    "Name" VARCHAR,
    "IsChecked" BOOLEAN,
    "Quantity" NUMERIC,
    "Store" VARCHAR,
    "Price" NUMERIC,
    "Brand" VARCHAR,
    "ProductUrl" TEXT,
    "ImageUrl" TEXT,
    "ProductId" VARCHAR,
    "Unit" VARCHAR,
    "AddedByUserId" BIGINT,
    "AddedByDisplayName" VARCHAR,
    "CreatedAt" TIMESTAMPTZ
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        s.item_id,
        s.group_id,
        g.name,
        s.name,
        s.is_checked,
        s.quantity,
        s.store,
        s.price,
        s.brand,
        s.product_url,
        s.image_url,
        s.product_id,
        s.unit,
        s.added_by_user_id,
        u.display_name,
        s.created_at
    FROM shopping_items s
    JOIN groups g ON g.group_id = s.group_id
    JOIN app_users u ON u.user_id = s.added_by_user_id
    WHERE s.item_id = p_item_id;
$$;

CREATE OR REPLACE FUNCTION fn_get_shopping_items(p_group_id BIGINT)
RETURNS TABLE (
    "ItemId" BIGINT,
    "GroupId" BIGINT,
    "GroupName" VARCHAR,
    "Name" VARCHAR,
    "IsChecked" BOOLEAN,
    "Quantity" NUMERIC,
    "Store" VARCHAR,
    "Price" NUMERIC,
    "Brand" VARCHAR,
    "ProductUrl" TEXT,
    "ImageUrl" TEXT,
    "ProductId" VARCHAR,
    "Unit" VARCHAR,
    "AddedByUserId" BIGINT,
    "AddedByDisplayName" VARCHAR,
    "CreatedAt" TIMESTAMPTZ
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        s.item_id,
        s.group_id,
        g.name,
        s.name,
        s.is_checked,
        s.quantity,
        s.store,
        s.price,
        s.brand,
        s.product_url,
        s.image_url,
        s.product_id,
        s.unit,
        s.added_by_user_id,
        u.display_name,
        s.created_at
    FROM shopping_items s
    JOIN groups g ON g.group_id = s.group_id
    JOIN app_users u ON u.user_id = s.added_by_user_id
    WHERE s.group_id = p_group_id
    ORDER BY s.is_checked, s.created_at DESC;
$$;

CREATE OR REPLACE FUNCTION fn_add_shopping_item(
    p_group_id BIGINT,
    p_name VARCHAR,
    p_added_by BIGINT,
    p_quantity NUMERIC DEFAULT 1,
    p_store VARCHAR DEFAULT NULL,
    p_price NUMERIC DEFAULT NULL,
    p_brand VARCHAR DEFAULT NULL,
    p_product_url TEXT DEFAULT NULL,
    p_image_url TEXT DEFAULT NULL,
    p_product_id VARCHAR DEFAULT NULL,
    p_unit VARCHAR DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_item_id BIGINT;
    v_qty NUMERIC := COALESCE(NULLIF(p_quantity, 0), 1);
BEGIN
    IF v_qty < 0 THEN
        RAISE EXCEPTION 'Quantity must be zero or greater'
            USING ERRCODE = '22023';
    END IF;

    INSERT INTO shopping_items (
        group_id, name, added_by_user_id, quantity,
        store, price, brand, product_url, image_url, product_id, unit
    )
    VALUES (
        p_group_id,
        TRIM(p_name),
        p_added_by,
        v_qty,
        NULLIF(TRIM(p_store), ''),
        p_price,
        NULLIF(TRIM(p_brand), ''),
        NULLIF(TRIM(p_product_url), ''),
        NULLIF(TRIM(p_image_url), ''),
        NULLIF(TRIM(p_product_id), ''),
        NULLIF(TRIM(p_unit), '')
    )
    RETURNING item_id INTO v_item_id;

    RETURN v_item_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_update_shopping_item(
    p_item_id BIGINT,
    p_name VARCHAR DEFAULT NULL,
    p_is_checked BOOLEAN DEFAULT NULL,
    p_quantity NUMERIC DEFAULT NULL,
    p_set_product BOOLEAN DEFAULT FALSE,
    p_store VARCHAR DEFAULT NULL,
    p_price NUMERIC DEFAULT NULL,
    p_brand VARCHAR DEFAULT NULL,
    p_product_url TEXT DEFAULT NULL,
    p_image_url TEXT DEFAULT NULL,
    p_product_id VARCHAR DEFAULT NULL,
    p_unit VARCHAR DEFAULT NULL
)
RETURNS TABLE (
    "ItemId" BIGINT,
    "GroupId" BIGINT,
    "Name" VARCHAR,
    "IsChecked" BOOLEAN,
    "Quantity" NUMERIC,
    "Store" VARCHAR,
    "Price" NUMERIC,
    "Brand" VARCHAR,
    "ProductUrl" TEXT,
    "ImageUrl" TEXT,
    "ProductId" VARCHAR,
    "Unit" VARCHAR,
    "AddedByUserId" BIGINT,
    "AddedByDisplayName" VARCHAR,
    "CreatedAt" TIMESTAMPTZ
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_name IS NULL
       AND p_is_checked IS NULL
       AND p_quantity IS NULL
       AND NOT COALESCE(p_set_product, FALSE) THEN
        RAISE EXCEPTION 'At least one field is required to update a shopping item'
            USING ERRCODE = '22023';
    END IF;

    IF p_name IS NOT NULL AND LENGTH(TRIM(p_name)) = 0 THEN
        RAISE EXCEPTION 'Item name cannot be empty'
            USING ERRCODE = '22023';
    END IF;

    IF p_quantity IS NOT NULL AND p_quantity < 0 THEN
        RAISE EXCEPTION 'Quantity must be zero or greater'
            USING ERRCODE = '22023';
    END IF;

    UPDATE shopping_items
       SET name = CASE WHEN p_name IS NULL THEN name ELSE TRIM(p_name) END,
           is_checked = COALESCE(p_is_checked, is_checked),
           quantity = COALESCE(p_quantity, quantity),
           store = CASE WHEN COALESCE(p_set_product, FALSE) THEN NULLIF(TRIM(p_store), '') ELSE store END,
           price = CASE WHEN COALESCE(p_set_product, FALSE) THEN p_price ELSE price END,
           brand = CASE WHEN COALESCE(p_set_product, FALSE) THEN NULLIF(TRIM(p_brand), '') ELSE brand END,
           product_url = CASE WHEN COALESCE(p_set_product, FALSE) THEN NULLIF(TRIM(p_product_url), '') ELSE product_url END,
           image_url = CASE WHEN COALESCE(p_set_product, FALSE) THEN NULLIF(TRIM(p_image_url), '') ELSE image_url END,
           product_id = CASE WHEN COALESCE(p_set_product, FALSE) THEN NULLIF(TRIM(p_product_id), '') ELSE product_id END,
           unit = CASE WHEN COALESCE(p_set_product, FALSE) THEN NULLIF(TRIM(p_unit), '') ELSE unit END
     WHERE item_id = p_item_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Shopping item % not found', p_item_id
            USING ERRCODE = 'P0002';
    END IF;

    RETURN QUERY
        SELECT *
        FROM fn_get_shopping_item(p_item_id);
END;
$$;

CREATE OR REPLACE FUNCTION fn_set_shopping_item_checked(
    p_item_id BIGINT,
    p_is_checked BOOLEAN
)
RETURNS TABLE (
    "ItemId" BIGINT,
    "GroupId" BIGINT,
    "Name" VARCHAR,
    "IsChecked" BOOLEAN,
    "Quantity" NUMERIC,
    "Store" VARCHAR,
    "Price" NUMERIC,
    "Brand" VARCHAR,
    "ProductUrl" TEXT,
    "ImageUrl" TEXT,
    "ProductId" VARCHAR,
    "Unit" VARCHAR,
    "AddedByUserId" BIGINT,
    "AddedByDisplayName" VARCHAR,
    "CreatedAt" TIMESTAMPTZ
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
        SELECT *
        FROM fn_update_shopping_item(p_item_id, NULL, p_is_checked);
END;
$$;


-- ============================================================================ 
-- database/14_shopping_for_user.sql
-- ============================================================================ 

-- Shopping lists across all groups for a user (home feed)

CREATE OR REPLACE FUNCTION fn_get_shopping_items_for_user(p_user_id BIGINT)
RETURNS TABLE (
    "ItemId" BIGINT,
    "GroupId" BIGINT,
    "GroupName" VARCHAR,
    "Name" VARCHAR,
    "IsChecked" BOOLEAN,
    "Quantity" NUMERIC,
    "Store" VARCHAR,
    "Price" NUMERIC,
    "Brand" VARCHAR,
    "ProductUrl" TEXT,
    "ImageUrl" TEXT,
    "ProductId" VARCHAR,
    "Unit" VARCHAR,
    "AddedByUserId" BIGINT,
    "AddedByDisplayName" VARCHAR,
    "CreatedAt" TIMESTAMPTZ
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        s.item_id,
        s.group_id,
        g.name,
        s.name,
        s.is_checked,
        s.quantity,
        s.store,
        s.price,
        s.brand,
        s.product_url,
        s.image_url,
        s.product_id,
        s.unit,
        s.added_by_user_id,
        u.display_name,
        s.created_at
    FROM shopping_items s
    JOIN groups g ON g.group_id = s.group_id
    JOIN group_members gm ON gm.group_id = s.group_id AND gm.user_id = p_user_id
    JOIN app_users u ON u.user_id = s.added_by_user_id
    ORDER BY s.is_checked, s.created_at DESC;
$$;


-- ============================================================================
-- Supabase Data API: lock down public schema
-- The ASP.NET API connects as postgres (bypasses RLS / owner privileges).
-- ============================================================================

ALTER TABLE public.app_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."groups" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.group_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bills ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bill_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bill_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shopping_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.group_invites ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.login_otps ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon, authenticated, PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM anon, authenticated, PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon, authenticated, PUBLIC;
