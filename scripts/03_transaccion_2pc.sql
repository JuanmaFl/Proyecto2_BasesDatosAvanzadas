-- ========================================================
-- SIMULACIÓN DE TWO-PHASE COMMIT (TRANSFERENCIA DE FONDOS)
-- ========================================================

-- FASE 1: PREPARE (Bloqueo de recursos)
-- Ejecutar en Nodo 2 (México)
BEGIN; 
UPDATE cuentas_mexico SET saldo = saldo - 500 WHERE cuenta_id = 2; 
PREPARE TRANSACTION 'tx_transfer_001';

-- Ejecutar en Nodo 3 (España)
BEGIN; 
UPDATE cuentas_espana SET saldo = saldo + 500 WHERE cuenta_id = 3; 
PREPARE TRANSACTION 'tx_transfer_001';

-- FASE 2: COMMIT PREPARED (Confirmación final)
-- Ejecutar en Nodo 2
COMMIT PREPARED 'tx_transfer_001';

-- Ejecutar en Nodo 3
COMMIT PREPARED 'tx_transfer_001';