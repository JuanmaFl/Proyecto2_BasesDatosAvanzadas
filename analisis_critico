# Análisis Crítico: Proyecto 2
 
---
 
## 1. Lo que nos dejó el proyecto
 
Este proyecto no fue solo un ejercicio técnico, sino que realmente nos cambió la forma de entender los sistemas distribuidos. Antes de implementarlo, conceptos como particionamiento, replicación y consenso distribuido eran principalmente teóricos, cosas de clase o diapositivas. Pero cuando los llevamos a la práctica, se volvieron mucho más claros.
 
Durante el desarrollo nos encontramos con problemas que normalmente no se ven en la teoría. Por ejemplo, el manejo de IPs dinámicas en AWS terminaba afectando la comunicación entre nodos, y nos tocaba reconfigurar conexiones casi cada vez que reiniciábamos. También vimos cómo una transacción podía quedar en estado pendiente indefinido cuando simulamos la caída del nodo coordinador después de un `PREPARE TRANSACTION`, lo que dejaba recursos bloqueados sin resolverse solos. En cambio, con CockroachDB sí fue posible ver cómo el sistema se recuperaba automáticamente sin que tuviéramos que intervenir.
 
En general, lo que nos quedó es que la complejidad en sistemas distribuidos no desaparece por usar herramientas más avanzadas, solo cambia de lugar.
 
---
 
## 2. De lo que vimos en clase a lo que pasó en realidad
 
### 2.1 El 2PC
 
En clase, el protocolo Two-Phase Commit se muestra como una solución clara para manejar transacciones distribuidas. Pero cuando lo implementamos en PostgreSQL, vimos que no es tan simple.
 
En uno de los experimentos, cuando simulamos la caída del nodo coordinador después del `PREPARE TRANSACTION`, las transacciones quedaban en estado pendiente indefinido, bloqueando recursos. No había forma automática de resolverlo, entonces tocaba hacerlo manualmente con `COMMIT PREPARED` o `ROLLBACK PREPARED`.
 
Esto deja claro que aunque el 2PC garantiza consistencia, también introduce un punto único de fallo. Y ahí es donde uno entiende mejor por qué en sistemas reales se usan alternativas como SAGA, que reemplaza el bloqueo distribuido por compensaciones: cada paso tiene una transacción compensatoria definida de antemano, así si algo falla no hay recursos colgados esperando a un coordinador.
 
### 2.2 CAP
 
Durante las pruebas medimos el impacto de `synchronous_commit` en PostgreSQL. La latencia pasó de aproximadamente 2.3 ms en modo asíncrono a unos 5.1 ms en modo síncrono.
 
Puede parecer poco, pero en realidad no lo es. Ese aumento viene de tener que esperar confirmación de la réplica remota antes de cerrar la transacción. Si esto se escala a muchas operaciones, termina afectando el rendimiento general, se acumulan esperas y la experiencia puede empeorar. Ahí es donde se vuelve claro que el teorema CAP sí tiene un impacto real.
 
### 2.3 Particionamiento
 
En los experimentos con particionamiento vimos que sí puede mejorar el rendimiento, pero no siempre.
 
Cuando las consultas coincidían con la clave de partición, el motor aplicaba partition pruning y solo accedía a lo necesario, lo cual hacía todo más rápido. Pero cuando había JOINs distribuidos, como con `postgres_fdw`, el rendimiento bajaba bastante. Los datos tenían que viajar entre nodos antes de completar la operación y eso metía latencia de red.
 
Entonces el particionamiento no es automáticamente bueno, depende mucho de cómo se diseñe.
 
### 2.4 CockroachDB
 
CockroachDB nos pareció muy bueno en términos de automatización. Hace sharding, replicación y manejo de fallos casi sin intervención. Pero también notamos varias cosas: tiene mayor latencia base en operaciones simples, consume más recursos y entender lo que pasa por dentro no es tan directo (Raft, rangos, leaseholders, etc.).
 
O sea, sí facilita muchas cosas, pero no es gratis.
 
---
 
## 3. Qué tan "transparente" es cada sistema
 
Uno de los objetivos era ver qué tan transparente era cada motor.
 
En PostgreSQL con `postgres_fdw`, la distribución es bastante visible. Con `EXPLAIN ANALYZE` se ven cosas como `Foreign Scan`, entonces uno sabe cuándo está trabajando con datos remotos.
 
En CockroachDB todo parece más transparente porque uno usa SQL normal sin preocuparse tanto por la distribución. Pero eso también puede ser engañoso. Si una consulta está mal diseñada, igual puede ser lenta y no es tan obvio por qué.
 
Entonces al final, la transparencia total no existe. Solo cambia qué tan fácil es ver los problemas.
 
---
 
## 4. Ejemplos reales
 
### 4.1 Bancolombia
 
Bancolombia trabaja con arquitecturas de alta disponibilidad que enfrentan exactamente los mismos trade-offs que trabajamos en este proyecto. Su estrategia combina réplicas de lectura para escalar consultas analíticas, particionamiento por rango temporal para gestionar el crecimiento de datos históricos, y separación de cargas transaccionales y analíticas en sistemas independientes. El equipo de ingeniería de datos de un banco de este tamaño tiene que tomar constantemente la misma decisión que medimos empíricamente: cuándo vale la pena pagar el costo de la consistencia sincrónica y cuándo no.
 
### 4.2 Mercado Pago
 
Mercado Pago, la plataforma de pagos de Mercado Libre, tiene arquitecturas de microservicios donde no todo opera con el mismo nivel de consistencia. Las transferencias de dinero sí son ACID y completamente consistentes. Pero mostrar el saldo actualizado en la pantalla del usuario puede tolerarse con un pequeño retraso. Ese patrón, conocido como CQRS, separa el modelo de escritura del modelo de lectura, optimizando cada lado del trade-off CAP de forma independiente. En la práctica, el usuario ve "Transferencia en proceso" mientras el sistema garantiza la atomicidad de la operación real, exactamente el tipo de decisión arquitectónica que aprendimos a valorar en este proyecto.
 
### 4.3 Google Spanner y CockroachDB
 
Google Spanner fue publicado en 2012 como la solución de Google para escalar transacciones ACID globalmente en sus sistemas de Ads y Payments. CockroachDB toma inspiración directa de ese diseño, replicando el mismo enfoque de consenso distribuido pero sin depender de hardware especializado. Nuestro experimento de auto-healing, donde CockroachDB continuó operando normalmente tras la caída del Nodo Colombia, es una versión a pequeña escala del mismo principio: el sistema mantiene disponibilidad y consistencia sin coordinación humana, algo que en Spanner ocurre a escala global con cientos de nodos.
 
---
 
## 5. Impacto en costos y administración
 
### 5.1 Costos de infraestructura
 
Durante el proyecto usamos instancias `t2.micro` de AWS Academy, que son las más económicas disponibles. Incluso ahí notamos que CockroachDB consumía más recursos que PostgreSQL, por el overhead constante de los algoritmos de consenso Raft.
 
Si trasladamos esto a un entorno productivo real, la diferencia es significativa. Un clúster de 3 nodos de CockroachDB requeriría instancias más grandes (al menos `t3.medium`) para funcionar bien, lo que puede triplicar el costo mensual frente a un setup equivalente con PostgreSQL. Por otro lado, una instancia gestionada como AWS RDS para PostgreSQL puede salir más barata que administrar manualmente los tres nodos, y encima ofrece backups automáticos, parches y failover sin trabajo adicional del equipo.
 
La conclusión es que no hay una opción universalmente más barata. Depende de si el equipo tiene la capacidad de administrar la infraestructura manualmente o si es más eficiente pagar por un servicio gestionado.
 
### 5.2 Carga administrativa
 
Configurar el sharding con `postgres_fdw`, la replicación, el 2PC y el failover manual en PostgreSQL nos tomó tiempo y varios errores. En CockroachDB, el mismo nivel de funcionalidad estaba disponible con mucho menos configuración.
 
En la vida real esa diferencia se traduce en horas de trabajo de un DBA especializado, que tiene un costo. Sin embargo, CockroachDB no elimina la necesidad de entender lo que está pasando: alguien tiene que saber interpretar los rangos, los leaseholders y el comportamiento de Raft cuando algo no funciona como se espera.
 
La comparación entre administrar todo manualmente, usar una base de datos distribuida como CockroachDB, o contratar un servicio gestionado en la nube no tiene una respuesta única. Para una startup pequeña, RDS puede ser lo más sensato. Para un sistema que necesita escalar geográficamente, CockroachDB tiene sentido. Para equipos con recursos técnicos y control total del stack, PostgreSQL bien configurado puede ser perfectamente suficiente.
 
---
 
## 6. Aprendizajes
 
### 6.1 El tema de las IPs
El manejo de IPs dinámicas en AWS fue más problemático de lo esperado. Cada vez que reiniciábamos instancias tocaba actualizar configuraciones.
 
### 6.2 El tiempo de configuración
Configurar PostgreSQL nos tomó bastante más tiempo de lo que pensábamos, sobre todo con FDW y replicación.
 
### 6.3 El costo del consenso
En CockroachDB, el uso de Raft implica un consumo constante de recursos. En máquinas pequeñas eso se nota bastante.
 
---
 
## 7. Lo que creíamos vs lo que entendimos después
 
Antes del proyecto teníamos claro lo teórico, pero al implementarlo entendimos mejor varias cosas.
 
La consistencia fuerte sí aumenta la latencia y se puede medir. El 2PC puede generar bloqueos serios si algo falla. Y el auto-healing funciona, pero no es inmediato.
 
También aprendimos que un mal particionamiento puede ser peor que no tenerlo.
 
---
 
## 8. Conclusión
 
Al final, no hay una base de datos que sea mejor en todos los casos. Todo depende del contexto, del volumen de datos, del equipo y de lo que se necesita.
 
PostgreSQL funciona muy bien en entornos más controlados. CockroachDB es útil cuando se necesita distribución y alta disponibilidad.
 
Lo más importante es que estos temas no se entienden completamente solo con teoría. Hay que probarlos para ver los problemas reales. Esto también deja claro que las decisiones de arquitectura no deberían basarse solo en lo que dice la teoría, sino en lo que se observa en la práctica.
