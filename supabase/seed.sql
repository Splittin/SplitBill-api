-- Demo users, group, bills, shopping, and chat (Teddy is user_id 1 for mobile)

DO $$
DECLARE
    v_teddy BIGINT;
    v_jess  BIGINT;
    v_sam   BIGINT;
    v_group BIGINT;
    v_bill1 BIGINT;
    v_bill2 BIGINT;
    v_bill3 BIGINT;
BEGIN
    IF EXISTS (SELECT 1 FROM app_users LIMIT 1) THEN
        RETURN;
    END IF;

    v_teddy := fn_create_user(
        'Teddy',
        'teddy@example.com',
        'teddy@payid.com.au',
        'Commonwealth Bank',
        '062-000',
        '1234 5678',
        NULL
    );

    v_jess := fn_create_user(
        'Jess',
        'jess@example.com',
        'jess.wong@payid.com.au',
        'ANZ',
        '033-000',
        '9988 7766',
        NULL
    );

    v_sam := fn_create_user(
        'Sam',
        'sam@example.com',
        '0412 345 678',
        'Commonwealth Bank',
        '062-149',
        '4455 6677',
        NULL
    );

    v_group := fn_create_group('Flatmates', v_teddy);
    PERFORM fn_add_group_member(v_group, v_jess);
    PERFORM fn_add_group_member(v_group, v_sam);

    -- Active bill: Dinner (Teddy raised; Jess/Sam pending)
    v_bill1 := fn_create_bill('Dinner at Luigi''s', 90, 'AUD', v_teddy, v_group);
    PERFORM fn_add_participant(v_bill1, v_teddy, 30, 'PAID');
    PERFORM fn_add_participant(v_bill1, v_jess, 30, 'PENDING');
    PERFORM fn_add_participant(v_bill1, v_sam, 30, 'PENDING');

    -- Verify bill: Sam marked paid, Teddy needs to confirm
    v_bill2 := fn_create_bill('Bunnings', 126.90, 'AUD', v_teddy, v_group);
    PERFORM fn_add_participant(v_bill2, v_teddy, 42.30, 'PAID');
    PERFORM fn_add_participant(v_bill2, v_jess, 42.30, 'PAID');
    PERFORM fn_add_participant(v_bill2, v_sam, 42.30, 'VERIFY');

    -- Settled archive bill
    v_bill3 := fn_create_bill('Coles', 52.40, 'AUD', v_teddy, v_group);
    PERFORM fn_add_participant(v_bill3, v_teddy, 17.47, 'PAID');
    PERFORM fn_add_participant(v_bill3, v_jess, 17.47, 'PAID');
    PERFORM fn_add_participant(v_bill3, v_sam, 17.46, 'PAID');
    UPDATE bills SET status = 'SETTLED' WHERE bill_id = v_bill3;

    PERFORM fn_add_shopping_item(v_group, 'Milk', v_jess);
    PERFORM fn_add_shopping_item(v_group, 'Paper towels', v_teddy);
    PERFORM fn_add_shopping_item(v_group, 'Dish soap', v_sam);
    UPDATE shopping_items SET is_checked = TRUE WHERE name = 'Dish soap' AND group_id = v_group;

    PERFORM fn_add_chat_message(v_group, v_jess, 'Paid my share for Woolworths 👍');
    PERFORM fn_add_chat_message(v_group, v_teddy, 'Thanks! Still waiting on Sam.');
    PERFORM fn_add_chat_message(v_group, v_sam, 'Will sort it tonight.');
END $$;
