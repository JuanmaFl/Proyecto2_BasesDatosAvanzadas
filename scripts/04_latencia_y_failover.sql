-- =================================================================
-- EXPERIMENTO DE LATENCIA (EJECUTADO EN EL PRIMARY - COLOMBIA)
-- =================================================================

-- Prueba Asíncrona (Latencia Baja: ~2.3ms)
CREATE TABLE prueba_latencia (id SERIAL PRIMARY KEY, texto VARCHAR(50));
INSERT INTO prueba_latencia (texto) VALUES ('Prueba Asincrona');

-- Activar Modo Sincrónico (Sacrificar latencia por consistencia)
-- (Se ejecutó a nivel de bash: echo "synchronous_standby_names = '*'" >> postgresql.conf)
SET synchronous_commit = on;

-- Prueba Sincrónica (Latencia Alta: ~5.1ms)
INSERT INTO prueba_latencia (texto) VALUES ('Prueba Sincrona');

-- =================================================================
-- PRUEBA DE FAILOVER (EJECUTADO EN RÉPLICA - MÉXICO)
-- =================================================================

-- 1. Intentar escribir en réplica (Falla por ser Read-Only)
INSERT INTO prueba_latencia (texto) VALUES ('Intento desde Mexico');

-- 2. Promover la réplica a Primary (Tras apagar Colombia)
-- Comando bash: pg_ctl promote -D /bitnami/postgresql/data

-- 3. Confirmar nueva soberanía
INSERT INTO prueba_latencia (texto) VALUES ('Nuevo Rey: Mexico');
SELECT * FROM prueba_latencia;