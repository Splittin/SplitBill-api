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
