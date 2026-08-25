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
