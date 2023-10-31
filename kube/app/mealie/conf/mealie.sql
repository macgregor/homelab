/* Create mealie database and user */
/* run as superuser */

/* replace $MEALIE_PG_PASSWORD with your unencrypted password string */
CREATE USER mealie WITH ENCRYPTED PASSWORD '$MEALIE_PG_PASSWORD';
SELECT 'CREATE DATABASE mealie WITH CONNECTION LIMIT 10' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'mealie')\gexec
ALTER DATABASE mealie OWNER TO mealie;

/* mealie will try to create this itself which requires superuser permissions */
CREATE EXTENSION pg_trgm; 