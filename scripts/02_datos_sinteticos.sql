-- EJECUTAR EN NODO 1 (COORDINADOR)

-- 1. Insertar 30,000 cuentas de forma masiva y aleatoria
INSERT INTO cuentas (cuenta_id, cliente_id, pais, saldo)
SELECT 
    x, 
    x + 1000, 
    CASE WHEN x % 3 = 0 THEN 'COLOMBIA' WHEN x % 3 = 1 THEN 'MEXICO' ELSE 'ESPANA' END, 
    round((random() * 5000 + 100)::numeric, 2)
FROM generate_series(4, 30004) AS x;

-- 2. Crear y poblar tabla clientes local para prueba de JOIN
CREATE TABLE clientes (
    cliente_id INT PRIMARY KEY,
    nombre VARCHAR(100)
);

INSERT INTO clientes (cliente_id, nombre)
SELECT x + 1000, 'Cliente ' || (x + 1000)
FROM generate_series(1, 30004) AS x;

-- 3. Análisis de JOIN Distribuido (Scatter-Gather)
EXPLAIN ANALYZE 
SELECT c.nombre, cta.pais, cta.saldo 
FROM clientes c 
JOIN cuentas cta ON c.cliente_id = cta.cliente_id 
WHERE cta.pais IN ('MEXICO', 'ESPANA') AND cta.saldo > 4800;