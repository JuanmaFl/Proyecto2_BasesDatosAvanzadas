# Proyecto 2: Arquitecturas Distribuidas - Escalabilidad, Replicación, Consistencia y Transacciones

**Materia:** SI3009 Bases de Datos Avanzadas, 2026-1  
**Programa:** Ingeniería de Sistemas  
**Integrantes:** Thomas Buitrago, Camila Martinez y Juan Manuel Florez.

---

## 1. Introducción y Objetivo
El volumen masivo de datos modernos ha llevado a las bases de datos al límite de la escalabilidad vertical. La solución estándar es distribuir la carga, pero esto introduce una complejidad extrema en términos de consistencia, latencia y tolerancia a fallos. 

El objetivo de este proyecto es diseñar, implementar y evaluar una arquitectura de base de datos distribuida para analizar empíricamente los compromisos (*trade-offs*) descritos por el Teorema CAP y el modelo PACELC. Para ello, contrastamos la configuración manual en un motor SQL clásico (**PostgreSQL**) frente al comportamiento automatizado de un motor NewSQL nativo de la nube (**CockroachDB**).

## 2. Contexto del Problema: Dominio Bancario
Seleccionamos el dominio de la **Banca (Cuentas y Transferencias)** debido a su estricta necesidad de consistencia transaccional (ACID). 
* **Modelo de Datos:** Tablas de clientes y cuentas bancarias.
* **Geodistribución:** Simulamos operaciones financieras divididas geográficamente en tres regiones: Colombia, México y España.
* **Volumen:** Se inyectaron mediante scripts generadores de datos sintéticos decenas de miles de registros para forzar al motor a demostrar su capacidad de particionamiento y enrutamiento en consultas analíticas (OLAP) y transaccionales (OLTP).

## 3. Arquitectura de la Solución e Infraestructura

La arquitectura se desplegó en **Amazon Web Services (AWS)** utilizando 3 instancias EC2 (`t2.micro`) con Docker, representando nuestros 3 nodos geográficos.

**Nota Técnica sobre el Enrutamiento (El reto de las IPs):**
Durante el desarrollo, tomamos la decisión arquitectónica y financiera de **no utilizar IPs Elásticas**. En entornos de producción reales, un cambio de IP es inaceptable y se mitiga mediante DNS (Route 53) o IPs estáticas. Sin embargo, en el entorno académico (Vocareum/AWS Academy), las IPs elásticas conllevan cobros por inactividad cuando las máquinas se detienen para ahorrar créditos. 
Dado que apagábamos la infraestructura al finalizar cada sesión de trabajo, **las instancias cambiaban de IP pública al reiniciarse**. Esto nos obligó a:
1. Actualizar dinámicamente los esquemas de red en PostgreSQL usando comandos `ALTER SERVER`.
2. Re-unir los nodos en CockroachDB ajustando los parámetros `--advertise-addr` tras cada reinicio.
Esta restricción, aunque tediosa operativamente, nos permitió comprender a bajo nivel cómo se establecen los túneles de comunicación TCP/IP entre fragmentos distribuidos.

---

## 4. Desarrollo de Experimentos y Fases Técnicas

### Fase 1 y 2: El enfoque Clásico (PostgreSQL) - Sharding y 2PC
Enfrentamos la complejidad de distribuir datos en un motor que no es distribuido nativamente.
* **Sharding Manual:** Utilizamos `postgres_fdw` para particionar horizontalmente la tabla de cuentas según el país. La lógica de enrutamiento quedó del lado del coordinador (Nodo Colombia).
* **El Reto del Join Distribuido:** Al cruzar la tabla local de `clientes` con la distribuida de `cuentas`, el `EXPLAIN ANALYZE` demostró el alto costo de red de los *Foreign Scans*.
* **Transacciones Distribuidas:** Implementamos manualmente el protocolo **Two-Phase Commit (2PC)** para simular una transferencia internacional. Ejecutamos `PREPARE TRANSACTION` en México y España antes de confirmar. Comprobamos críticamente que, si el coordinador cae en este punto, los recursos quedan bloqueados (lock), penalizando la disponibilidad.

### Fase 3: Replicación, Latencia y CAP (PostgreSQL)
Desplegamos una topología Líder-Seguidor.
* **Experimento de Latencia (CAP):** Probamos el balance entre latencia y consistencia alterando el parámetro `synchronous_commit`. En modo asíncrono, la escritura tomó **~2.3 ms**. Al forzar consistencia fuerte (esperando el acuse de recibo de la réplica en otra IP), la latencia se duplicó a **~5.1 ms**. 
* **Failover:** Simulamos la caída del nodo principal y tuvimos que intervenir manualmente ejecutando `pg_ctl promote` en una réplica para recuperar la operatividad, demostrando un RTO (Recovery Time Objective) dependiente del administrador.

### Fase 4: La Revolución NewSQL (CockroachDB)
* **Particionamiento y Sharding Transparente:** A diferencia de Postgres, aquí solo ejecutamos un `CREATE TABLE`. El motor dividió los datos en rangos de 512MB y los distribuyó sin intervención nuestra.
* **Replicación Raft y Auto-Healing:** Al apagar abruptamente el nodo principal, no hubo caída del servicio. CockroachDB identificó la ausencia mediante *heartbeats* y reeligió un nuevo líder de rango automáticamente. Las escrituras en el nodo sobreviviente (México) se procesaron de inmediato, evidenciando **Zero Downtime**.

---

## 5. Análisis Comparativo PACELC y Dimensiones Técnicas

| Dimensión | PostgreSQL (SQL Clásico) | CockroachDB (NewSQL) |
| :--- | :--- | :--- |
| **Particionamiento** | Manual. Requiere `postgres_fdw`, particiones por lista/rango creadas explícitamente en cada nodo. | Automático (Auto-sharding). El motor balancea los rangos transparentemente según la carga. |
| **Replicación** | Configuración manual Master/Slave. Unidireccional. | Nativa Multi-Activo. Basada en el protocolo de consenso Raft. |
| **Manejo de Transacciones** | Requiere orquestación manual del protocolo 2PC, propenso a bloqueos si falla el coordinador. | Transacciones distribuidas ACID nativas y transparentes. |
| **Consistencia vs Latencia** | Configurable, pero global. Si se exige consistencia estricta, la latencia penaliza severamente el throughput. | Usa consistencia fuerte por defecto. Penaliza latencia, pero mitiga moviendo el *Leaseholder* cerca de donde más se consulta. |
| **Manejo de Fallos (PACELC)** | En caso de Partición de red (P), sacrifica Disponibilidad (A) para mantener Consistencia (C) o requiere intervención manual. | Ante Particiones (P), el sistema favorece Consistencia (C) si hay quórum, recuperándose automáticamente (Auto-healing). |
| **Complejidad de Administración** | Alta. Requiere DBA especializado para gestionar caídas, backups por nodo y re-enrutamientos. | Baja a nivel operativo, el clúster se auto-gestiona, aunque su arquitectura interna es de extrema complejidad. |

---

## 6. Análisis Crítico y Conclusiones del Equipo

1. **Impacto en Costos y Administración:** No todo lo que brilla es oro. Si bien CockroachDB eliminó la carga operativa de configurar Sharding y Failovers (que en Postgres nos tomó horas de configuración de archivos `.conf` y manejo de roles), este tipo de bases de datos NewSQL consumen considerablemente más memoria RAM y CPU para mantener los algoritmos de consenso (Raft) y la metradata distribuida. Para empresas pequeñas, el costo de infraestructura en la nube de un clúster NewSQL puede no justificar el beneficio frente a una instancia gestionada de Postgres (ej. AWS RDS).
2. **La ilusión de la transparencia:** Las bases de datos NewSQL prometen abstracción total ("funciona como un Postgres normal"), pero como ingenieros comprobamos que ignorar la topología física subyacente es un error. Si un desarrollador hace un `JOIN` ineficiente en CockroachDB sin entender dónde residen los datos, el rendimiento colapsará por la latencia de red, igual que ocurrió en nuestro experimento con `postgres_fdw`.
3. **Sistemas en el Mundo Real:** La industria financiera real utiliza arquitecturas híbridas. Las transacciones core suelen manejarse con consistencia estricta (sacrificando milisegundos), mientras que servicios como la actualización del saldo visible en la app móvil utilizan patrones de persistencia eventual o CQRS para favorecer la disponibilidad total.

## 7. Estructura del Repositorio

* `/infra`: Archivos de configuración y `docker-compose.yml` utilizados para levantar las instancias.
* `/scripts`: Scripts SQL conteniendo la lógica de creación de bases de datos, FDW, simulaciones masivas e implementación de 2PC.
* `/capturas`: [Ver el README interactivo de evidencias visuales aquí](./capturas/README.md) detallando las pruebas de latencia, planes de ejecución y failovers de ambos sistemas.