/* This will result in loss of all data */
/* run as superuser */
DROP SCHEMA public CASCADE;
CREATE SCHEMA public;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO public;
REASSIGN OWNED BY mealie to postgres;
DROP OWNED BY mealie;
DROP USER IF EXISTS mealie;