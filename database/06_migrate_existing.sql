-- Idempotent upgrades for databases created before groups/chat/shopping existed.

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

ALTER TABLE bills
    ADD COLUMN IF NOT EXISTS group_id BIGINT REFERENCES groups (group_id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS shopping_items (
    item_id         BIGSERIAL PRIMARY KEY,
    group_id        BIGINT        NOT NULL REFERENCES groups (group_id) ON DELETE CASCADE,
    name            VARCHAR(200)  NOT NULL,
    is_checked      BOOLEAN       NOT NULL DEFAULT FALSE,
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

CREATE INDEX IF NOT EXISTS ix_bills_group ON bills (group_id);
CREATE INDEX IF NOT EXISTS ix_group_members_user ON group_members (user_id);
CREATE INDEX IF NOT EXISTS ix_shopping_group ON shopping_items (group_id);
CREATE INDEX IF NOT EXISTS ix_chat_group ON chat_messages (group_id, created_at);
