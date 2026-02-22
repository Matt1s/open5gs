-- Dialplan rules for SMS number translation
-- Translate short numbers and numbers with country code to E.164 format

INSERT INTO dialplan (dpid, pr, match_op, match_exp, match_len, subst_exp, repl_exp, attrs) 
VALUES 
(1, 1, 1, '^1234567892$', 0, '^(.*)$', '+491234567892', ''),
(1, 1, 1, '^1234567893$', 0, '^(.*)$', '+491234567893', ''),
(1, 1, 1, '^491234567892$', 0, '^(.*)$', '+491234567892', ''),
(1, 1, 1, '^491234567893$', 0, '^(.*)$', '+491234567893', '');
