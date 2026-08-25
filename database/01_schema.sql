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
