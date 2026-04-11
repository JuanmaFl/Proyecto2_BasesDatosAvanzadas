-- =================================================================
-- FASE 4: COCKROACHDB (NEWSQL Y AUTO-HEALING)
-- =================================================================

-- 1. Creación de base de datos y tabla (Nodo 1 - Colombia)
CREATE DATABASE banco_global;
USE banco_global;

CREATE TABLE cuentas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(), 
    cliente STRING, 
    saldo DECIMAL
);

-- 2. Inserción masiva de datos simulados
INSERT INTO cuentas (cliente, saldo) 
SELECT 
    'Cliente_' || id::STRING, 
    (random() * 10000)::DECIMAL(10,2) 
FROM generate_series(1, 100) AS g(id);

-- 3. Comprobación de Replicación Automática y Sharding
-- Resultado esperado: replicas = {1, 2, 3} (Se copia en los 3 nodos automáticamente)
SHOW RANGES FROM TABLE cuentas;

-- =================================================================
-- PRUEBA DE AUTO-HEALING (EJECUTADO EN NODO 2 - TRAS APAGAR NODO 1)
-- =================================================================

USE banco_global;

-- El clúster sigue vivo y permite lecturas
SELECT count(*) FROM cuentas;

-- El clúster permite escrituras (No hay read-only constraint como en Postgres)
INSERT INTO cuentas (cliente, saldo) VALUES ('Sobreviviente Failover', 9999.99);
SELECT * FROM cuentas WHERE cliente = 'Sobreviviente Failover';