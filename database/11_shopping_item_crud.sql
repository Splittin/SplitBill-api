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
