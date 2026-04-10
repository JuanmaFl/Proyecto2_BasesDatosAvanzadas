-- ==========================================
-- EJECUTAR EN NODO 2 (MÉXICO)
-- ==========================================
CREATE TABLE cuentas_mexico (
    cuenta_id INT PRIMARY KEY,
    cliente_id INT,
    pais VARCHAR(50) CHECK (pais = 'MEXICO'),
    saldo DECIMAL(15, 2) DEFAULT 0
);

-- ==========================================
-- EJECUTAR EN NODO 3 (ESPAÑA)
-- ==========================================
CREATE TABLE cuentas_espana (
    cuenta_id INT PRIMARY KEY,
    cliente_id INT,
    pais VARCHAR(50) CHECK (pais = 'ESPANA'),
    saldo DECIMAL(15, 2) DEFAULT 0
);

-- ==========================================
-- EJECUTAR EN NODO 1 (COLOMBIA / COORDINADOR)
-- ==========================================
CREATE EXTENSION postgres_fdw;

-- Registrar Nodos Remotos (Ajustar IPs según AWS)
CREATE SERVER nodo_mexico FOREIGN DATA WRAPPER postgres_fdw OPTIONS (host '<IP_MEXICO>', dbname 'banco_db', port '5432');
CREATE USER MAPPING FOR admin SERVER nodo_mexico OPTIONS (user 'admin', password 'password');

CREATE SERVER nodo_espana FOREIGN DATA WRAPPER postgres_fdw OPTIONS (host '<IP_ESPANA>', dbname 'banco_db', port '5432');
CREATE USER MAPPING FOR admin SERVER nodo_espana OPTIONS (user 'admin', password 'password');

-- Crear Tabla Maestra Particionada
CREATE TABLE cuentas (
    cuenta_id INT,
    cliente_id INT,
    pais VARCHAR(50),
    saldo DECIMAL(15, 2) DEFAULT 0
) PARTITION BY LIST (pais);

-- Fragmento Local
CREATE TABLE cuentas_colombia PARTITION OF cuentas FOR VALUES IN ('COLOMBIA');

-- Conectar Fragmentos Remotos
IMPORT FOREIGN SCHEMA public LIMIT TO (cuentas_mexico) FROM SERVER nodo_mexico INTO public;
ALTER TABLE cuentas ATTACH PARTITION cuentas_mexico FOR VALUES IN ('MEXICO');

IMPORT FOREIGN SCHEMA public LIMIT TO (cuentas_espana) FROM SERVER nodo_espana INTO public;
ALTER TABLE cuentas ATTACH PARTITION cuentas_espana FOR VALUES IN ('ESPANA');