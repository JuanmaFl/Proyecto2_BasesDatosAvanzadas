# Proyecto 2: Arquitecturas Distribuidas - Escalabilidad, Replicación, Consistencia y Transacciones

**Materia:** SI3009 Bases de Datos Avanzadas, 2026-1  
**Programa:** Ingeniería de Sistemas  
**Integrantes:** Thomas Buitrago, Camila Martinez y Juan Manuel Florez.

---

## 1. Introducción y Objetivo
El volumen masivo de datos modernos ha llevado a las bases de datos al límite de la escalabilidad vertical. La solución estándar es distribuir la carga, pero esto introduce una complejidad extrema en términos de consistencia, latencia y tolerancia a fallos. 

El objetivo de este proyecto es diseñar, implementar y evaluar una arquitectura de base de datos distribuida para analizar empíricamente los compromisos (*trade-offs*) descritos por el Teorema CAP y el modelo PACELC. 

Para ello, contrastamos la configuración manual en un motor SQL clásico (**PostgreSQL**) en relación al comportamiento automatizado de un motor NewSQL nativo de la nube (**CockroachDB**).

---

## 2. Contexto del Problema: Dominio Bancario

Seleccionamos el dominio de la **Banca (Cuentas y Transferencias)** por su estricta necesidad de consistencia transaccional (ACID).

### Modelo de Datos
* **cuentas:** `cuenta_id`, `cliente_id`, `pais`, `saldo`.
* **clientes:** `cliente_id`, `nombre`.

### Geodistribución
Simulamos operaciones financieras divididas geográficamente en tres regiones: Colombia, México y España.

| Nodo | IP (AWS) | Región | Rol en PostgreSQL | Rol en CockroachDB |
| :--- | :--- | :--- | :--- | :--- |
| Nodo 1 | 100.53.191.219 | Colombia | Coordinador / Primary | Nodo activo (Leaseholder) |
| Nodo 2 | 98.93.43.92 | México | Fragmento remoto / Réplica | Nodo activo |
| Nodo 3 | 54.145.59.62 | España | Fragmento remoto / Réplica | Nodo activo |

### Volumen de Datos
Se inyectaron mediante scripts generadores de datos sintéticos decenas de miles de registros para forzar al motor a demostrar su capacidad de particionamiento y enrutamiento.

| Tabla | Registros | Estrategia |
| :--- | :--- | :--- |
| `cuentas` | 30.001 | LIST por país (~10.000 por nodo) |
| `clientes` | 30.004 | Local en coordinador |

---

## 3. Arquitectura de la Solución e Infraestructura

La arquitectura se desplegó en **Amazon Web Services (AWS)** utilizando 3 instancias EC2 (`t2.micro`) con Docker.

```text
┌──────────────────────────────────────────────────────────────┐
│                    AWS — us-east-1b                          │
│                                                              │
│  ┌──────────────────┐  ┌─────────────────┐  ┌─────────────┐  │
│  │      Nodo 1      │  │      Nodo 2     │  │    Nodo 3   │  │
│  │     Colombia     │  │      México     │  │    España   │  │
│  │ 100.53.191.219   │  │  98.93.43.92    │  │ 54.145.59.62│  │
│  │    t2.micro      │  │    t2.micro     │  │    t2.micro │  │
│  │                  │  │                 │  │             │  │
│  │  ┌────────────┐  │  │ ┌───────────┐   │  │ ┌─────────┐ │  │
│  │  │ PostgreSQL │  │  │ │PostgreSQL │   │  │ │Postgres │ │  │
│  │  │(Coordinador│  │  │ │ (Réplica/ │   │  │ │(Réplica/│ │  │
│  │  │ /Primary)  │  │  │ │ Fragmento)│   │  │ │Fragment)│ │  │
│  │  └────────────┘  │  │ └───────────┘   │  │ └─────────┘ │  │
│  │  ┌────────────┐  │  │ ┌───────────┐   │  │ ┌─────────┐ │  │
│  │  │CockroachDB │  │  │ │CockroachDB│   │  │ │Cockroach│ │  │
│  │  │ v23.1.14   │◄─┼──┼►│ v23.1.14  │ ◄─┼──┼►│v23.1.14 │ │  │
│  │  │  (Raft)    │  │  │ │  (Raft)   │   │  │ │ (Raft)  │ │  │
│  │  └────────────┘  │  │ └───────────┘   │  │ └─────────┘ │  │
│  └──────────────────┘  └─────────────────┘  └─────────────┘  │
│                                                              │
│                   Red VPC — us-east-1b                       │
└──────────────────────────────────────────────────────────────┘

```

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
* **El Reto del Join Distribuido:** Al cruzar la tabla local de `clientes` con la distribuida de `cuentas`, el `EXPLAIN ANALYZE` demostró el alto costo de red de los *Foreign Scans*, los cuales confirman que PostgreSQL delega el filtro a los nodos remotos, pero los resultados viajan primero por red antes de ejecutar el `Nested Loop` de forma local.
* **Transacciones Distribuidas:** Implementamos manualmente el protocolo **Two-Phase Commit (2PC)** para simular una transferencia internacional. Ejecutamos `PREPARE TRANSACTION` en México y España antes de confirmar. Comprobamos críticamente que, si el coordinador cae en este punto, los recursos quedan bloqueados (lock), penalizando la disponibilidad. Sin coordinador no podemos resolver automaticmante la incertidumbre, por lo que hay que intervenir manuelmente con `COMMIT PREPARED` o `ROLLBACK PREPARED`.

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

## 6. Análisis de Resultados Experimentales y Conclusiones del Equipo

### 6.1 Distribución de Datos y Eficiencia del Sharding

Los resultados de la inserción masiva de datos evidencian una distribución prácticamente uniforme de los registros entre los nodos geográficos, con aproximadamente **10,000 cuentas por país**. Esto valida que la estrategia de particionamiento por lista (`LIST`) basada en el atributo `pais` permite un balance adecuado de carga.

Sin embargo, esta eficiencia en almacenamiento no se traduce directamente en eficiencia en consulta. El análisis del `EXPLAIN ANALYZE` del `JOIN` distribuido revela un comportamiento crítico: el motor ejecuta múltiples operaciones de tipo `Foreign Scan`, lo que implica que los datos deben ser recuperados desde nodos remotos antes de completar el `Nested Loop` localmente.

El tiempo total de ejecución (**~65.668 ms**) es significativamente mayor al esperado para una consulta local, lo que evidencia que:

* El costo dominante no es computacional, sino **latencia de red**.
* PostgreSQL **no optimiza globalmente consultas distribuidas**, sino que delega ejecución parcial y luego centraliza el procesamiento.
* El coordinador se convierte en un **cuello de botella lógico**.

Esto confirma el principio de PACELC:

| En ausencia de partición (Else), el sistema sacrifica latencia (L) debido a la distribución física de los datos.

### 6.2 Transacciones Distribuidas y Consistencia (2PC)

La implementación del protocolo **Two-Phase Commit (2PC)** demuestra correctamente la capacidad de mantener propiedades ACID en un entorno distribuido.

Durante la fase de preparación (`PREPARE TRANSACTION`), se observa que:

* Las operaciones en México (débito) y España (crédito) quedan en estado intermedio.
* Los recursos permanecen **bloqueados** hasta que el coordinador decide el `COMMIT`.

Tras la ejecución final, los resultados reflejan consistencia global en los saldos, confirmando que:

* La **atomicidad distribuida se cumple correctamente**.
* No existen estados intermedios visibles para el usuario.

No obstante, este modelo introduce un trade-off crítico:

* Si el nodo coordinador falla después del `PREPARE`, las transacciones quedan en estado incierto.
* Esto genera **bloqueo de recursos (locks persistentes)** y requiere intervención manual.

Este comportamiento evidencia directamente el modelo CAP:

* PostgreSQL prioriza **Consistencia (C)** sobre **Disponibilidad (A)**.
* Ante fallos, el sistema no puede progresar automáticamente.

### 6.3 Replicación y Trade-off Consistencia vs Latencia (CAP)

El experimento de latencia muestra una diferencia clara:

* Escritura asíncrona: **~2.3 ms**
* Escritura síncrona: **~5.15 ms**

Esto implica un incremento de más del **120% en latencia** al exigir confirmación de réplica.

La razón técnica es que en modo síncrono:

* El nodo primario debe esperar confirmación de escritura física en al menos una réplica remota.
* La latencia de red entre nodos (AWS) se vuelve parte del tiempo de commit.

Esto confirma empíricamente:

* La consistencia fuerte en sistemas distribuidos tiene un costo directo en rendimiento.
* El throughput del sistema se ve afectado negativamente al aumentar el número de réplicas síncronas.

Desde la perspectiva PACELC:

* **ELC (Else Latency vs Consistency)** → PostgreSQL permite elegir:
  * Baja latencia (asincrónico, eventual consistency)
  * Alta consistencia (sincrónico, mayor latencia)
 
### 6.4 Restricciones Operativas y Modelo Primary-Replica

El intento de escritura en un nodo réplica genera el error:

| `"cannot execute INSERT in a read-only transaction"`

Esto valida que:

* PostgreSQL implementa un modelo **Single-Writer (Primary)**.
* Las réplicas son estrictamente de solo lectura.

Este diseño:

* Simplifica la consistencia
* Pero limita la escalabilidad en escritura

En escenarios de alta concurrencia, esto implica:

* El nodo primario se convierte en un **punto único de presión (write bottleneck)**.

### 6.5 Tolerancia a Fallos y Failover

El experimento de failover demuestra que, tras la caída del nodo primario:

* Es necesario ejecutar manualmente `pg_ctl promote`.
* Una vez promovido, el nodo acepta escrituras correctamente.

Aunque el sistema logra recuperarse sin pérdida de datos, se identifican limitaciones importantes:

* El tiempo de recuperación **(RTO)** depende del operador.
* Existe riesgo de errores humanos durante la promoción.
* No hay mecanismo automático de elección de líder.

Esto implica que:

* PostgreSQL es **fault-tolerant, pero no fault-resilient de forma autónoma**.

## 6.6 Arquitectura NewSQL: Sharding y Replicación Transparente

En CockroachDB, la inserción de datos y el análisis de `SHOW RANGES` evidencian que:

* El sistema distribuye automáticamente los datos en rangos.
* Cada rango tiene réplicas en los nodos `{1,2,3}`.

Esto elimina completamente:

* La necesidad de definir particiones manuales
* La lógica de enrutamiento en la aplicación

Sin embargo, esta abstracción implica:

* Overhead constante de replicación
* Mayor consumo de recursos (CPU/RAM)

### 6.7 Consistencia Distribuida mediante Raft

A diferencia de PostgreSQL, CockroachDB no utiliza 2PC manual visible.

En su lugar:

* Implementa el protocolo de consenso **Raft**
* Cada escritura requiere acuerdo de la mayoría (**quórum**)

Esto permite:

* Consistencia fuerte por defecto
* Eliminación del coordinador central

El trade-off es claro:

* Mayor latencia base en comparación con escrituras locales
* Pero sin riesgo de estados intermedios o bloqueos manuales

### 6.8 Tolerancia a Fallos y Auto-Healing (CockroachDB)

El experimento de caída de nodo demuestra que:

* El sistema continúa operando sin interrupción (**Zero Downtime**)
* Lecturas y escrituras siguen funcionando desde otros nodos
* El clúster mantiene consistencia (conteo correcto de registros)

Esto es posible porque:

* Raft reelige automáticamente un líder de rango
* El sistema mantiene quórum activo

Comparado con PostgreSQL:

| Característica | PostgreSQL (SQL Clásico) | CockroachDB (NewSQL) |
| :--- | :--- | :--- |
| Failover | Manual. | Automático. |
| Tiempo de recuperación | Dependiente del operador. | Inmediato. |
| Disponibilidad | Reducida durante el fallo. | Alta (si hay quórum). |

Esto evidencia un diseño claramente orientado a:

* **Alta disponibilidad sin intervención humana**
* Sistemas distribuidos a escala real

### 6.9 Síntesis Final: Validación Empírica de CAP y PACELC

A partir de los resultados experimentales, se puede concluir:

**PostgreSQL**
* CAP: **CP (Consistencia + Tolerancia a partición)**
* PACELC:
  * P → sacrifica disponibilidad
  * E → permite elegir entre latencia o consistencia
* Ventaja: control total
* Desventaja: alta complejidad operativa

**CockroachDB**
* CAP: **CP con alta disponibilidad percibida**
* PACELC:
  * P → mantiene consistencia con quórum
  * E → sacrifica latencia para garantizar consistencia fuerte
* Ventaja: automatización total
* Desventaja: mayor costo computacional

### Conclusión del análisis

Los experimentos confirman que:

* La distribución de datos introduce inevitablemente **latencia de red como factor dominante**
* La consistencia fuerte en sistemas distribuidos **no es gratuita**
* PostgreSQL expone explícitamente la complejidad del mundo distribuido
* CockroachDB abstrae dicha complejidad, pero la internaliza mediante algoritmos de consenso

En términos prácticos:

| PostgreSQL ofrece control y eficiencia en entornos controlados, mientras que CockroachDB ofrece resiliencia y automatización para sistemas distribuidos a gran escala.

1. **Impacto en Costos y Administración:** No todo lo que brilla es oro. Si bien CockroachDB eliminó la carga operativa de configurar Sharding y Failovers (que en Postgres nos tomó horas de configuración de archivos `.conf` y manejo de roles), este tipo de bases de datos NewSQL consumen considerablemente más memoria RAM y CPU para mantener los algoritmos de consenso (Raft) y la metradata distribuida. Para empresas pequeñas, el costo de infraestructura en la nube de un clúster NewSQL puede no justificar el beneficio frente a una instancia gestionada de Postgres (ej. AWS RDS).
2. **La ilusión de la transparencia:** Las bases de datos NewSQL prometen abstracción total ("funciona como un Postgres normal"), pero como ingenieros comprobamos que ignorar la topología física subyacente es un error. Si un desarrollador hace un `JOIN` ineficiente en CockroachDB sin entender dónde residen los datos, el rendimiento colapsará por la latencia de red, igual que ocurrió en nuestro experimento con `postgres_fdw`.
3. **Sistemas en el Mundo Real:** La industria financiera real utiliza arquitecturas híbridas. Las transacciones core suelen manejarse con consistencia estricta (sacrificando milisegundos), mientras que servicios como la actualización del saldo visible en la app móvil utilizan patrones de persistencia eventual o CQRS para favorecer la disponibilidad total.

## 7. Estructura del Repositorio

* `/infra`: Archivos de configuración y `docker-compose.yml` utilizados para levantar las instancias.
* `/scripts`: Scripts SQL conteniendo la lógica de creación de bases de datos, FDW, simulaciones masivas e implementación de 2PC.
* `/Capturas`: [Ver el README interactivo de evidencias visuales aquí](./capturas/README.md) detallando las pruebas de latencia, planes de ejecución y failovers de ambos sistemas.
* `/analisis_critico`: Analisis proyecto anexo.
