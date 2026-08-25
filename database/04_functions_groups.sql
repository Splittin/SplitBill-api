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
