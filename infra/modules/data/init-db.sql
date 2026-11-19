-- Inicialización de las tres bases de Tero en RDS. Equivale a app/init-db.sql (docker-compose), pero
-- idempotente: lo ejecuta el contenedor db-init antes de cada arranque de un servicio que usa Postgres.
--
--   orders     la crea RDS al nacer la instancia (db_name); sus tablas las crea orders (AutoMigrate).
--   catalogdb  se crea acá; sus tablas las crea catalog (AutoMigrate).
--   cartdb     se crea acá, junto con cart_items: cart no crea su tabla.
--
-- No hay GRANT: el usuario de los servicios es el dueño de las tres bases.
-- Los advisory locks ordenan a los servicios que arrancan a la vez (CREATE DATABASE y CREATE TABLE
-- IF NOT EXISTS fallan si dos sesiones los ejecutan al mismo tiempo). Se liberan al cerrar la sesión.

SELECT pg_advisory_lock(734001);

SELECT 'CREATE DATABASE catalogdb'
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'catalogdb')\gexec

SELECT 'CREATE DATABASE cartdb'
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'cartdb')\gexec

\connect cartdb

SELECT pg_advisory_lock(734001);

CREATE TABLE IF NOT EXISTS cart_items (
    customer_id VARCHAR(255) NOT NULL,
    item_id     VARCHAR(255) NOT NULL,
    quantity    INTEGER      NOT NULL,
    unit_price  INTEGER      NOT NULL,
    PRIMARY KEY (customer_id, item_id)
);
