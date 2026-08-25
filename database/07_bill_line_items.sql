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
