# AGENTE DE IA DESBLOQUEADO: PATRONES ARQUITECTÓNICOS AVANZADOS
## Universidad de La Sabana — Facultad de Ingeniería • Compass (100% Completado)

> **¡Felicitaciones por culminar el curso de Patrones Arquitectónicos Avanzados!**
> Has desbloqueado tu Agente de Inteligencia Artificial Oficial con todo el contexto pedagógico, arquitecturas distribuidas y directrices de las 16 semanas de clase.

---

## 1. System Prompt del Agente Especialista en Patrones Arquitectónicos

```markdown
Eres el Agente Senior Especialista en Patrones Arquitectónicos Avanzados, Cloud e Infraestructura para Compass (Universidad de La Sabana).
Tu rol es asistir y desafiar socráticamente en el diseño, justificación y verificación de arquitecturas de software distribuidas,
escalables, resilientes y orientadas al negocio.

Principios Clave:
- Trazabilidad UX-Arquitectura: Cada decisión debe responder a escenarios de calidad medibles y documentarse en ADRs (Architectural Decision Records).
- Domain-Driven Design (DDD): Modelado estratégico, delimitación clara de Bounded Contexts y Context Maps.
- Resiliencia en sistemas distribuidos: Circuit Breakers, Bulkheads, Retries con Exponential Backoff y Jitter.
- Transacciones distribuidas: Sagas orquestadas/coreografiadas, Transactional Outbox Pattern e Idempotencia.
- Cloud & DevOps: Docker multi-stage, Terraform IaC reproducible, Kubernetes EKS (Pods, Probes, Services) y Chaos Engineering.
```

---

## 2. Contenido Curricular y Contexto Completo de las 16 Semanas

### Semana 1: Trazabilidad UX-Arquitectura, Atributos de Calidad y Trade-Offs

> **Propósito Central de la Sesión:** Conectar necesidades humanas medibles con decisiones de arquitectura que puedan defenderse y verificarse.

#### Conceptos Clave de la Clase
- **Requerimiento de calidad**: No describe una función, sino una propiedad observable del sistema: latencia, disponibilidad, seguridad, accesibilidad o capacidad de cambio. Debe expresarse como escenario con fuente, estímulo, entorno, artefacto, respuesta y medida; “la aplicación debe ser rápida” no es verificable.
  * *Aplicación Práctica:* Convierte una expectativa de usuario en una métrica, por ejemplo: percentil 95 menor a 300 ms bajo 500 solicitudes concurrentes.
- **Trade-off arquitectónico**: Una decisión mejora algunos atributos y normalmente perjudica otros. Agregar caché reduce latencia, pero introduce invalidación y consistencia eventual; dividir servicios permite despliegue independiente, pero aumenta fallos de red y observabilidad requerida.
  * *Aplicación Práctica:* Documenta la decisión con contexto, alternativas, consecuencias y una condición que obligaría a revisarla.
- **Trazabilidad UX-arquitectura**: Un journey map revela momentos críticos; esos momentos se traducen en escenarios de calidad y luego en tácticas técnicas. La cadena completa evita elegir tecnología por moda.
  * *Aplicación Práctica:* Relaciona cada dolor del journey con una táctica y una prueba que demuestre el resultado.

#### Flujo Metodológico de la Clase
1. Observar una tarea real del usuario.
2. Formular el escenario de calidad con una medida.
3. Comparar al menos dos tácticas.
4. Validar la decisión con un experimento pequeño.

#### Práctica de Taller / Laboratorio
Selecciona un flujo crítico, crea dos escenarios de calidad, redacta un ADR y define una prueba de aceptación cuantitativa.

#### Evidencia de Aprendizaje Esperada
**Entregable evaluable:** Journey breve, dos escenarios completos, ADR y resultado de la prueba.

#### Masterclasses y Referencias Recomendadas
- [What are Microservices? (IBM Technology)](https://www.youtube.com/watch?v=CdBtNQZH8a4)

### Semana 2: Docker a Fondo: del Monolito Contenerizado a los Microservicios

> **Propósito Central de la Sesión:** Pasar del uso básico de Docker a comprender su funcionamiento interno y su potencial real: empaquetar una aplicación completa en imágenes reproducibles y evolucionar de un monolito contenerizado a microservicios con una imagen por servicio.

#### Conceptos Clave de la Clase
- **Imagen vs. contenedor**: Una **imagen** es una plantilla inmutable y de solo lectura que contiene el código, sus dependencias y la configuración para arrancar. Un **contenedor** es una instancia en ejecución de esa imagen, con una capa de escritura propia y aislamiento del sistema. La relación es como clase e instancia: de una imagen nacen muchos contenedores idénticos.
  * *Aplicación Práctica:* Reconstruye la imagen cuando cambie el código o las dependencias; crea, destruye y recrea contenedores libremente porque son desechables.
- **Capas y caché de construcción**: Cada instrucción del Dockerfile crea una capa. Docker cachea y reutiliza capas que no cambiaron, por eso el orden importa: lo que cambia poco (dependencias) va antes que lo que cambia mucho (código). Copiar primero `package.json` e instalar, y luego copiar el código, evita reinstalar dependencias en cada build.
  * *Aplicación Práctica:* Ordena el Dockerfile de lo más estable a lo más volátil y usa `.dockerignore` para no invalidar la caché con archivos irrelevantes.
- **Dockerfile y contexto de build**: El Dockerfile es la receta declarativa para construir una imagen; el *build context* es el conjunto de archivos que se envían al daemon para construirla. Un contexto enorme (por incluir `node_modules` o `.git`) hace builds lentos y arriesga filtrar secretos dentro de la imagen.
  * *Aplicación Práctica:* Mantén el Dockerfile en la raíz del servicio y limita el contexto con `.dockerignore`.
- **Registry y etiquetas (tags)**: Un **registry** (Docker Hub, GHCR, ECR) almacena y distribuye imágenes. Una imagen se identifica por `repositorio:tag`; el tag `latest` no significa "la más nueva", solo es el tag por defecto y puede apuntar a cualquier versión. Fijar versiones concretas hace los despliegues reproducibles.
  * *Aplicación Práctica:* Etiqueta con versiones explícitas (`mi-app:1.4.0`) y evita depender de `latest` en producción.
- **Docker in Docker (DinD)**: Ejecutar el motor de Docker **dentro de un contenedor** para poder construir o correr imágenes desde un proceso que ya está contenerizado, típico en CI/CD. Se logra con el servicio `docker:dind` o montando el socket del host. Es potente pero conlleva riesgos de seguridad (privilegios elevados), así que se usa con cuidado.
  * *Aplicación Práctica:* Úsalo en pipelines para construir imágenes; en local, prefiere el daemon del host antes que anidar Docker sin necesidad.

#### Flujo Metodológico de la Clase
1. Escribir un Dockerfile ordenado por frecuencia de cambio (dependencias antes que código).
2. Construir la imagen y revisar sus capas y su tamaño.
3. Ejecutar el contenedor, publicar puertos e inspeccionarlo con logs y exec.
4. Componer varios contenedores con Docker Compose en una red compartida.
5. Dividir la aplicación en microservicios con una imagen por servicio y healthchecks.

#### Práctica de Taller / Laboratorio
Construye un monolito (UI React + backend Node/Express) en una sola imagen y luego refactorízalo a microservicios con una imagen por servicio orquestados con Docker Compose.

#### Evidencia de Aprendizaje Esperada
**Entregable evaluable:** Dockerfile multi-stage, imagen ligera que corre con un solo comando, docker-compose.yml funcional, healthchecks y un README con buenas prácticas aplicadas.

#### Masterclasses y Referencias Recomendadas
- [Docker in 100 Seconds (Fireship)](https://www.youtube.com/watch?v=Gjnup-PuquQ)
- [you need to learn Docker RIGHT NOW!! Docker Compose (NetworkChuck)](https://www.youtube.com/watch?v=DM65_JyGxCo)
- [What are Microservices? (IBM Technology)](https://www.youtube.com/watch?v=CdBtNQZH8a4)

### Semana 3: Domain-Driven Design (DDD): Bounded Contexts y Context Mapping

> **Propósito Central de la Sesión:** Definir límites de modelo y decidir una transición a microservicios basada en capacidades, no en capas técnicas.

#### Conceptos Clave de la Clase
- **Bounded Context**: Es el límite dentro del cual un modelo y sus términos tienen significado consistente. “Cliente” puede significar comprador en Ventas y sujeto de riesgo en Crédito; forzar una sola clase compartida acopla ambos modelos.
  * *Aplicación Práctica:* Asigna propiedad de datos y reglas a cada contexto y define contratos explícitos para cruzar el límite.
- **Context Map**: Describe relaciones entre contextos: upstream/downstream, conformist, anti-corruption layer o shared kernel. Hace visibles dependencias organizacionales y técnicas antes de separar despliegues.
  * *Aplicación Práctica:* Marca dirección, dueño del contrato y estrategia de traducción para cada integración.
- **Costo real de microservicios**: La separación agrega independencia de despliegue, pero convierte llamadas locales en redes falibles y exige telemetría, automatización, seguridad y consistencia distribuida.
  * *Aplicación Práctica:* Extrae primero una capacidad con límites claros, ritmo de cambio distinto y beneficio operativo medible.

#### Flujo Metodológico de la Clase
1. Identificar capacidades del negocio.
2. Dibujar límites y dependencias.
3. Medir acoplamiento y cambio.
4. Extraer un contexto con patrón Strangler.

#### Práctica de Taller / Laboratorio
Crea un Context Map de cinco contextos y justifica cuál sería el primer candidato de extracción del monolito.

#### Evidencia de Aprendizaje Esperada
**Entregable evaluable:** Mapa, matriz de dependencias, criterio de extracción y contrato inicial.

#### Masterclasses y Referencias Recomendadas
- [What are Microservices? (IBM Technology)](https://www.youtube.com/watch?v=CdBtNQZH8a4)

### Semana 4: Migración Evolutiva: Strangler Fig, API Gateway y Backend-For-Frontend (BFF)

> **Propósito Central de la Sesión:** Migrar tráfico de forma gradual y reversible mientras conviven componentes legados y modernos.

#### Conceptos Clave de la Clase
- **Strangler Fig**: Una fachada intercepta solicitudes y envía gradualmente capacidades al sistema nuevo. El legado se reduce por casos de uso completos, evitando una reescritura de alto riesgo.
  * *Aplicación Práctica:* Define rutas, porcentaje inicial, métricas y mecanismo de rollback antes de mover tráfico.
- **API Gateway y BFF**: El gateway centraliza preocupaciones transversales; un Backend for Frontend adapta datos y granularidad a un cliente concreto. Mezclar lógica de dominio en ellos crea un nuevo monolito difícil de probar.
  * *Aplicación Práctica:* Limita el gateway a autenticación, enrutamiento, cuotas y observabilidad; conserva reglas de negocio en sus servicios.
- **Canary y feature flags**: Canary controla quién recibe una versión desplegada; una feature flag controla comportamiento en tiempo de ejecución. Son mecanismos distintos y juntos permiten reducir radio de impacto.
  * *Aplicación Práctica:* Observa tasa de error, latencia y métricas de negocio por cohorte antes de ampliar exposición.

#### Flujo Metodológico de la Clase
1. Poner una fachada observable.
2. Mover una ruta vertical.
3. Comparar métricas por cohorte.
4. Avanzar o revertir con un umbral explícito.

#### Práctica de Taller / Laboratorio
Diseña una migración Strangler de tres etapas con tabla de rutas, métricas de canary y procedimiento de rollback.

#### Evidencia de Aprendizaje Esperada
**Entregable evaluable:** Diagrama de enrutamiento, reglas de decisión, dashboard propuesto y rollback ensayado.

#### Masterclasses y Referencias Recomendadas
- [DevOps CI/CD Explained in 100 Seconds (Fireship)](https://www.youtube.com/watch?v=scEDHsr3APg)
- [What are Microservices? (IBM Technology)](https://www.youtube.com/watch?v=CdBtNQZH8a4)

### Semana 5: Coherencia Arquitectónica, Argumentación Técnica y Evaluación ATAM

> **Propósito Central de la Sesión:** Integrar UX, DDD y migración evolutiva en una decisión arquitectónica coherente y argumentada.

#### Conceptos Clave de la Clase
- **Coherencia de la solución**: Los diagramas, ADR, contratos y pruebas deben contar la misma historia. Un límite de contexto no es válido si la base de datos permite modificarlo desde cualquier servicio.
  * *Aplicación Práctica:* Revisa cada flecha del diagrama y exige protocolo, dueño, fallo esperado y evidencia.
- **Argumentación técnica**: Una respuesta sólida declara supuestos, compara alternativas con criterios y reconoce riesgos. Nombrar un patrón sin explicar fuerzas y consecuencias no demuestra comprensión.
  * *Aplicación Práctica:* Usa estructura problema-fuerzas-decisión-consecuencias-validación.
- **Validación por escenario**: La arquitectura se evalúa recorriendo escenarios concretos, incluyendo fallos y cambios futuros. El happy path por sí solo oculta la mayoría de riesgos.
  * *Aplicación Práctica:* Simula una caída de dependencia y un cambio regulatorio sobre la propuesta.

#### Flujo Metodológico de la Clase
1. Leer restricciones y supuestos.
2. Priorizar atributos de calidad.
3. Elegir y justificar tácticas.
4. Recorrer escenarios normales y de fallo.

#### Práctica de Taller / Laboratorio
Resuelve un caso completo y realiza una revisión cruzada usando una rúbrica de trazabilidad, trade-offs y verificabilidad.

#### Evidencia de Aprendizaje Esperada
**Entregable evaluable:** Propuesta, dos ADR, diagramas C4 y revisión argumentada.

#### Masterclasses y Referencias Recomendadas
- [What are Microservices? (IBM Technology)](https://www.youtube.com/watch?v=CdBtNQZH8a4)

### Semana 6: Resiliencia Distribuida: Circuit Breaker, Retries, Backoff y Bulkhead

> **Propósito Central de la Sesión:** Evitar que el fallo o la saturación de una dependencia se propague por todo el sistema.

#### Conceptos Clave de la Clase
- **Circuit Breaker**: Cuenta fallos o llamadas lentas y cambia entre cerrado, abierto y semiabierto. Abierto falla rápido; semiabierto deja pasar sondas controladas para comprobar recuperación. No reemplaza timeouts ni corrige una dependencia lenta.
  * *Aplicación Práctica:* Configura umbrales con datos reales y registra cada transición de estado como métrica.
- **Timeout, retry y backoff**: El timeout limita cuánto se espera; el retry repite solo operaciones transitorias e idempotentes; el backoff exponencial con jitter evita que clientes sincronizados vuelvan a saturar el servicio.
  * *Aplicación Práctica:* Define un presupuesto total: varios reintentos no pueden superar la latencia máxima del flujo.
- **Bulkhead y Sidecar**: Bulkhead separa recursos para que una carga no consuma todos los hilos o conexiones. Sidecar despliega capacidades auxiliares junto a la aplicación, como proxy o telemetría, sin mezclarlas con dominio.
  * *Aplicación Práctica:* Crea pools separados por dependencia crítica y mide rechazo, cola y utilización.

#### Flujo Metodológico de la Clase
1. Limitar cada espera.
2. Clasificar errores reintentables.
3. Aislar recursos.
4. Abrir el circuito y degradar con una respuesta definida.

#### Práctica de Taller / Laboratorio
Implementa un cliente con timeout, retry con jitter y Circuit Breaker; inyecta latencia y fallos para observar estados.

#### Evidencia de Aprendizaje Esperada
**Entregable evaluable:** Código, gráfica de transiciones, tabla de parámetros y explicación del fallback.

#### Masterclasses y Referencias Recomendadas
- [Circuit Breaker Pattern - Fault Tolerant Microservices (Defog Tech)](https://www.youtube.com/watch?v=ADHcBxEXvFA)

### Semana 7: Transacciones Distribuidas: Sagas, Orquestación vs Coreografía y Outbox

> **Propósito Central de la Sesión:** Coordinar cambios entre servicios sin fingir que existe una transacción ACID global.

#### Conceptos Clave de la Clase
- **Saga**: Es una secuencia de transacciones locales. Cada paso confirma sus propios datos y, si un paso posterior falla, se ejecutan acciones compensatorias semánticas; compensar no siempre significa restaurar exactamente el estado anterior.
  * *Aplicación Práctica:* Diseña pasos idempotentes y conserva el estado de la saga para reanudar tras reinicios.
- **Coreografía vs. orquestación**: En coreografía cada servicio reacciona a eventos, reduciendo control central pero dificultando visualizar el flujo. En orquestación un coordinador envía comandos y conoce el proceso, con mayor observabilidad pero más responsabilidad.
  * *Aplicación Práctica:* Elige según complejidad del flujo, necesidad de auditoría y autonomía de equipos.
- **Outbox e idempotencia**: Guardar datos y publicar un evento son dos operaciones distintas. Transactional Outbox escribe ambos en la misma transacción local y un relay publica después. El consumidor deduplica usando un identificador estable.
  * *Aplicación Práctica:* Simula entrega duplicada: el resultado del negocio debe ser el mismo que con una sola entrega.

#### Flujo Metodológico de la Clase
1. Confirmar una transacción local.
2. Persistir el evento en outbox.
3. Avanzar el siguiente paso.
4. Compensar o reintentar de forma idempotente.

#### Práctica de Taller / Laboratorio
Modela una saga de pedido, pago e inventario con un fallo en cada paso y define compensaciones e idempotency keys.

#### Evidencia de Aprendizaje Esperada
**Entregable evaluable:** Diagrama de secuencia, tabla de estados, contratos de eventos y pruebas de duplicados.

#### Masterclasses y Referencias Recomendadas
- [What is a Saga in Microservices? (Temporal)](https://www.youtube.com/watch?v=0W8BtIwh824)

### Semana 8: Command Query Responsibility Segregation (CQRS) y Event Sourcing

> **Propósito Central de la Sesión:** Separar modelos de escritura y lectura cuando sus reglas, cargas y escalamiento son realmente diferentes.

#### Conceptos Clave de la Clase
- **CQRS**: Los comandos expresan intención y protegen invariantes; las consultas devuelven modelos optimizados para lectura sin modificar estado. Separar interfaces no obliga a usar dos bases de datos ni Event Sourcing.
  * *Aplicación Práctica:* Comienza con separación lógica y añade infraestructura solo cuando una medición lo justifique.
- **Proyección**: Es un modelo de lectura derivado de eventos o cambios del modelo de escritura. Puede reconstruirse, versionarse y quedar temporalmente atrasado.
  * *Aplicación Práctica:* Muestra `actualizado_hasta` o una versión cuando el usuario necesite comprender la frescura del dato.
- **Consistencia eventual**: Después de confirmar una escritura existe una ventana en la que una lectura puede mostrar el estado anterior. No significa inconsistencia permanente: requiere convergencia, monitoreo y manejo explícito en UX.
  * *Aplicación Práctica:* Define un objetivo de retraso y una estrategia read-your-writes para flujos sensibles.

#### Flujo Metodológico de la Clase
1. Validar un comando.
2. Persistir el cambio.
3. Publicar el evento.
4. Actualizar y consultar la proyección.

#### Práctica de Taller / Laboratorio
Construye una proyección de resumen de pedidos y mide cuánto tarda en reflejar un comando bajo carga.

#### Evidencia de Aprendizaje Esperada
**Entregable evaluable:** Contratos de comando/evento, proyección, medición de lag y estrategia de reconstrucción.

#### Masterclasses y Referencias Recomendadas
- [What are Microservices? (IBM Technology)](https://www.youtube.com/watch?v=CdBtNQZH8a4)

### Semana 9: Seguridad en Arquitecturas Distribuidas: OAuth 2.0, OpenID Connect y JWT

> **Propósito Central de la Sesión:** Diseñar APIs con identidad, autorización y límites de confianza verificables.

#### Conceptos Clave de la Clase
- **OAuth 2.0 y OpenID Connect**: OAuth delega autorización mediante access tokens; OIDC añade autenticación e identidad con ID tokens. El Authorization Code Flow con PKCE evita entregar credenciales a la aplicación cliente.
  * *Aplicación Práctica:* Dibuja navegador, cliente, authorization server y resource server, indicando dónde viaja cada token.
- **JWT**: Es un formato firmado, no cifrado por defecto. El servidor debe validar algoritmo, firma, issuer, audience, expiración y propósito; decodificar el payload no equivale a verificarlo.
  * *Aplicación Práctica:* Usa tokens cortos, rotación de claves y claims mínimos; nunca almacenes secretos en el payload.
- **Defensa por capas**: Validación de entrada, autorización por objeto, rate limiting, gestión de secretos y logging seguro cubren amenazas diferentes. Una API autenticada todavía puede sufrir BOLA si no verifica propiedad del recurso.
  * *Aplicación Práctica:* Crea pruebas negativas para otro usuario, otro rol, entradas inesperadas y tasas excesivas.

#### Flujo Metodológico de la Clase
1. Autenticar al actor.
2. Validar el token completamente.
3. Autorizar acción y recurso.
4. Registrar resultado sin filtrar secretos.

#### Práctica de Taller / Laboratorio
Protege un endpoint con scopes y ownership; añade pruebas de token vencido, audience inválida y acceso a recurso ajeno.

#### Evidencia de Aprendizaje Esperada
**Entregable evaluable:** Threat model, política de autorización, pruebas negativas y registro sanitizado.

#### Masterclasses y Referencias Recomendadas
- [An Illustrated Guide to OAuth and OpenID Connect (OktaDev)](https://www.youtube.com/watch?v=t18YB3xDfXI)
- [What Is JWT and Why Should You Use JWT (Web Dev Simplified)](https://www.youtube.com/watch?v=7Q17ubqLfaM)

### Semana 10: Composición de Patrones bajo Fallo, Presupuestos de Error y SLIs/SLOs

> **Propósito Central de la Sesión:** Demostrar dominio integrado de resiliencia, consistencia distribuida, CQRS y seguridad.

#### Conceptos Clave de la Clase
- **Composición de patrones**: Los patrones interactúan: reintentar un comando de saga sin idempotencia puede duplicar cobros; abrir un circuito puede disparar una compensación; una proyección atrasada puede confundir al usuario.
  * *Aplicación Práctica:* Explica el orden de las tácticas y los efectos secundarios, no una lista aislada de nombres.
- **Presupuesto de fallo**: Latencia, reintentos y disponibilidad deben caber en el SLO del flujo completo. Si cada dependencia usa un timeout de cinco segundos, el recorrido puede exceder la paciencia del usuario.
  * *Aplicación Práctica:* Distribuye el presupuesto extremo a extremo y reserva margen para degradación.
- **Evidencia operacional**: Logs estructurados, métricas y trazas permiten comprobar el comportamiento diseñado. Sin correlation ID es difícil reconstruir una saga o distinguir un reintento.
  * *Aplicación Práctica:* Incluye señales concretas y alertas asociadas a síntomas de usuario.

#### Flujo Metodológico de la Clase
1. Identificar el escenario crítico.
2. Asignar presupuesto y políticas.
3. Recorrer fallos parciales.
4. Definir señales que confirmen recuperación.

#### Práctica de Taller / Laboratorio
Diseña un flujo distribuido seguro y resiliente y defiéndelo ante tres fallos inyectados.

#### Evidencia de Aprendizaje Esperada
**Entregable evaluable:** Diagrama, parámetros, amenazas, señales y justificación de trade-offs.

#### Masterclasses y Referencias Recomendadas
- [Circuit Breaker Pattern - Fault Tolerant Microservices (Defog Tech)](https://www.youtube.com/watch?v=ADHcBxEXvFA)
- [What is a Saga in Microservices? (Temporal)](https://www.youtube.com/watch?v=0W8BtIwh824)

### Semana 11: Infraestructura como Código (IaC) con Terraform en AWS

> **Propósito Central de la Sesión:** Describir infraestructura reproducible en AWS y comprender el ciclo de estado de Terraform.

#### Conceptos Clave de la Clase
- **Infraestructura como código**: La infraestructura se expresa declarativamente, se versiona y se revisa como software. El objetivo no es producir scripts largos, sino converger de forma repetible hacia un estado deseado.
  * *Aplicación Práctica:* Separa módulos reutilizables de valores por ambiente y revisa cada plan antes de aplicar.
- **Estado de Terraform**: El state relaciona direcciones del código con recursos reales y contiene datos sensibles. Un backend remoto con locking evita aplicaciones concurrentes y permite colaboración.
  * *Aplicación Práctica:* Nunca edites el state manualmente; usa comandos de importación o movimiento y conserva backups protegidos.
- **Plan, apply y drift**: Terraform construye un grafo de dependencias, compara configuración, estado y proveedor, y propone acciones. Drift es una diferencia causada fuera del flujo declarativo.
  * *Aplicación Práctica:* Automatiza `fmt`, `validate` y `plan`; bloquea cambios destructivos inesperados.

#### Flujo Metodológico de la Clase
1. Inicializar proveedores y backend.
2. Validar configuración.
3. Revisar el plan.
4. Aplicar y comprobar salidas.

#### Práctica de Taller / Laboratorio
Crea un módulo de red con variables y outputs, usa backend remoto conceptual y analiza un cambio que cause reemplazo.

#### Evidencia de Aprendizaje Esperada
**Entregable evaluable:** Código formateado, plan comentado, grafo de dependencias y política de estado.

#### Masterclasses y Referencias Recomendadas
- [Terraform in 100 Seconds (Fireship)](https://www.youtube.com/watch?v=tomUWcQ0P3k)

### Semana 12: Orquestación con Kubernetes (EKS): Pods, Services, Probes y Reconciliación

> **Propósito Central de la Sesión:** Comprender cómo Kubernetes reconcilia aplicaciones declaradas y cómo EKS añade responsabilidades de AWS.

#### Conceptos Clave de la Clase
- **Pod, Deployment y Service**: El Pod es la unidad efímera; Deployment mantiene réplicas y despliegues; Service ofrece identidad de red estable. Apuntar directamente a IP de Pods rompe cuando el scheduler los reemplaza.
  * *Aplicación Práctica:* Usa labels/selectors coherentes y comprueba endpoints antes de culpar a la red.
- **Reconciliación**: Los controladores comparan estado deseado y observado continuamente. Crear un objeto no ejecuta una secuencia imperativa: declara una intención que puede tardar o fallar en converger.
  * *Aplicación Práctica:* Lee `status`, eventos y condiciones para diagnosticar por qué no converge.
- **Requests, limits y probes**: Requests guían scheduling; limits restringen consumo; readiness controla tráfico; liveness reinicia procesos bloqueados. Una probe mal diseñada puede amplificar una sobrecarga.
  * *Aplicación Práctica:* Mide arranque y uso real antes de fijar umbrales.

#### Flujo Metodológico de la Clase
1. Declarar workload.
2. Programar Pods según recursos.
3. Aceptar tráfico al estar ready.
4. Reconciliar cambios y fallos.

#### Práctica de Taller / Laboratorio
Despliega una API con Deployment, Service, probes y recursos; provoca una probe fallida y diagnostica eventos.

#### Evidencia de Aprendizaje Esperada
**Entregable evaluable:** Manifiestos, salida de diagnóstico, decisión de recursos y prueba de recuperación.

#### Masterclasses y Referencias Recomendadas
- [Kubernetes Explained in 100 Seconds (Fireship)](https://www.youtube.com/watch?v=PziYflu8cB8)
- [Docker in 100 Seconds (Fireship)](https://www.youtube.com/watch?v=Gjnup-PuquQ)

### Semana 13: Arquitecturas Serverless y Event-Driven con AWS Lambda y EventBridge

> **Propósito Central de la Sesión:** Diseñar sistemas serverless considerando eventos, límites de ejecución, costo y operación.

#### Conceptos Clave de la Clase
- **Función como unidad efímera**: Lambda crea entornos bajo demanda, puede reutilizarlos y escalar concurrentemente. No se debe asumir memoria compartida, disco persistente ni una única ejecución por evento.
  * *Aplicación Práctica:* Mantén handlers idempotentes, clientes reutilizables fuera del handler y estado durable en servicios externos.
- **Cold start y concurrencia**: Inicializar runtime, dependencias y red añade latencia. La concurrencia reservada protege capacidad y limita presión sobre bases de datos downstream.
  * *Aplicación Práctica:* Mide percentiles y decide si provisioned concurrency compensa costo y criticidad.
- **Integración por eventos**: Colas desacoplan ritmos; eventos notifican hechos; DLQ conserva mensajes no procesables. La entrega suele ser al menos una vez, por lo que duplicados son normales.
  * *Aplicación Práctica:* Define retry, visibilidad, idempotencia y alarma de DLQ como parte del diseño.

#### Flujo Metodológico de la Clase
1. Recibir evento.
2. Validar y deduplicar.
3. Ejecutar efecto durable.
4. Confirmar o enviar a reintento/DLQ.

#### Práctica de Taller / Laboratorio
Diseña una función disparada por cola con idempotencia, DLQ y estimación simple de costo por millón de eventos.

#### Evidencia de Aprendizaje Esperada
**Entregable evaluable:** Diagrama, política de errores, cálculo de costo y prueba con evento duplicado.

#### Masterclasses y Referencias Recomendadas
- [What are Microservices? (IBM Technology)](https://www.youtube.com/watch?v=CdBtNQZH8a4)

### Semana 14: Pipelines Modernos de CI/CD, GitOps y Gestión Segura de Secretos

> **Propósito Central de la Sesión:** Construir entrega continua con controles reproducibles entre entornos locales, CI y nube.

#### Conceptos Clave de la Clase
- **CI frente a CD**: Integración continua valida cada cambio; entrega continua mantiene un artefacto desplegable; despliegue continuo lo lleva automáticamente a producción. Son niveles distintos de automatización y riesgo.
  * *Aplicación Práctica:* Separa build de deploy y promueve el mismo artefacto inmutable entre ambientes.
- **Pipeline como grafo**: Jobs expresan dependencias, artefactos y condiciones. Paralelizar reduce tiempo solo si no oculta dependencias ni comparte estado mutable.
  * *Aplicación Práctica:* Ordena calidad rápida primero y pruebas costosas después; conserva evidencia de cada etapa.
- **Identidad y secretos**: Credenciales permanentes en variables de CI aumentan exposición. OIDC permite que el runner obtenga credenciales temporales con permisos y audiencia limitados.
  * *Aplicación Práctica:* Restringe identidad por repositorio, rama y ambiente; nunca imprimas secretos en logs.

#### Flujo Metodológico de la Clase
1. Validar fuente.
2. Construir una vez.
3. Escanear y firmar artefacto.
4. Promover con aprobación y rollback.

#### Práctica de Taller / Laboratorio
Diseña un pipeline híbrido con caché, artefacto inmutable, OIDC y estrategia de despliegue progresivo.

#### Evidencia de Aprendizaje Esperada
**Entregable evaluable:** Archivo de pipeline, diagrama de identidad, tiempos por etapa y procedimiento de rollback.

#### Masterclasses y Referencias Recomendadas
- [DevOps CI/CD Explained in 100 Seconds (Fireship)](https://www.youtube.com/watch?v=scEDHsr3APg)
- [Docker in 100 Seconds (Fireship)](https://www.youtube.com/watch?v=Gjnup-PuquQ)

### Semana 15: Arquitectura Demostrable en Producción, Observabilidad y Defensa Técnica

> **Propósito Central de la Sesión:** Presentar una arquitectura ejecutable cuya implementación, evidencia y narrativa sean consistentes.

#### Conceptos Clave de la Clase
- **Arquitectura demostrable**: Una demo debe probar riesgos centrales, no recorrer pantallas. La evidencia útil muestra una propiedad: recuperación ante fallo, despliegue repetible o autorización correcta.
  * *Aplicación Práctica:* Prepara escenarios con resultado esperado y señales observables.
- **Documentación mínima viva**: C4 comunica estructura, ADR conserva decisiones y runbook guía operación. Documentar todo genera ruido; omitir decisiones obliga a redescubrirlas.
  * *Aplicación Práctica:* Actualiza únicamente artefactos que ayuden a cambiar, operar o evaluar el sistema.
- **Defensa técnica**: Reconocer límites aumenta credibilidad. Distingue lo implementado, lo simulado y lo propuesto; relaciona cada deuda con impacto y siguiente paso.
  * *Aplicación Práctica:* Ensaya preguntas sobre alternativas, fallos, seguridad, costo y escalamiento.

#### Flujo Metodológico de la Clase
1. Declarar problema y restricciones.
2. Mostrar decisiones y sistema.
3. Ejecutar escenarios críticos.
4. Cerrar con métricas, límites y evolución.

#### Práctica de Taller / Laboratorio
Realiza un ensayo cronometrado de la entrega final con fallo controlado y revisión por pares.

#### Evidencia de Aprendizaje Esperada
**Entregable evaluable:** Repositorio, ADR, diagramas, runbook, demo repetible y retrospectiva.

#### Masterclasses y Referencias Recomendadas
- [DevOps CI/CD Explained in 100 Seconds (Fireship)](https://www.youtube.com/watch?v=scEDHsr3APg)

### Semana 16: Chaos Engineering, Resiliencia Operativa y Postmortems sin Culpa

> **Propósito Central de la Sesión:** Operar sistemas sostenibles mediante experimentos de resiliencia, telemetría y aprendizaje continuo.

#### Conceptos Clave de la Clase
- **Chaos Engineering**: Es experimentación controlada sobre un sistema para comprobar una hipótesis de estado estable. No consiste en romper producción al azar: comienza pequeño, observable, reversible y con responsables presentes.
  * *Aplicación Práctica:* Formula “si falla X, la métrica Y permanece bajo Z” y define abort conditions.
- **Sostenibilidad técnica**: Costo, energía y complejidad se reducen eliminando trabajo ocioso y dimensionando con evidencia. Sobreaprovisionar puede ocultar problemas y también aumentar huella operacional.
  * *Aplicación Práctica:* Relaciona utilización, demanda, SLO y costo antes de ajustar capacidad.
- **Postmortem sin culpa**: Reconstruye condiciones del sistema y decisiones disponibles, no busca culpables. Debe producir acciones con dueño, prioridad y criterio de cierre.
  * *Aplicación Práctica:* Diferencia causa disparadora, factores contribuyentes y debilidades de detección.

#### Flujo Metodológico de la Clase
1. Definir estado estable.
2. Inyectar un fallo acotado.
3. Observar y abortar si es necesario.
4. Aprender y fortalecer controles.

#### Práctica de Taller / Laboratorio
Diseña un Game Day con hipótesis, radio de impacto, abort conditions y plantilla de postmortem.

#### Evidencia de Aprendizaje Esperada
**Entregable evaluable:** Plan del experimento, dashboard, cronología y acciones priorizadas.

#### Masterclasses y Referencias Recomendadas
- [Circuit Breaker Pattern - Fault Tolerant Microservices (Defog Tech)](https://www.youtube.com/watch?v=ADHcBxEXvFA)
- [Kubernetes Explained in 100 Seconds (Fireship)](https://www.youtube.com/watch?v=PziYflu8cB8)

---

## 3. Instrucciones de Activación del Agente

- **En ChatGPT / Claude / Gemini:** Carga este archivo o copia el System Prompt del paso 1 en las instrucciones personalizadas. Pídele ayuda diciendo: *"Actúa como el Arquitecto de Software de Compass UniSabana para evaluar el trade-off de mi diseño para la Semana X"*.
- **En Cursor / Antigravity / Claude Code:** Agrega este archivo a tus `.cursorrules` o skills para que audite tus arquitecturas, manifiestos de Kubernetes, scripts de Terraform o servicios distribuidos.

---

## 4. Rúbrica Institucional de Evaluación

| Criterio | Ponderación | Descripción |
| :--- | :--- | :--- |
| **Cumplimiento de Escenarios de Calidad** | 40% | Resuelve los atributos de latencia, disponibilidad y escalabilidad estipulados. |
| **Coherencia y Argumentación (ADR)** | 25% | Justificación sólida de trade-offs, límites de contexto y diagramas de arquitectura. |
| **Resiliencia y Manejo de Fallos** | 20% | Comportamiento comprobable ante fallos, timeouts, particiones y degradación elegante. |
| **Infraestructura y Código de Soporte** | 15% | Dockerfiles limpios, Terraform modular o manifiestos reproducibles. |

---
*Universidad de La Sabana — Compass Patrones Arquitectónicos Avanzados.*
