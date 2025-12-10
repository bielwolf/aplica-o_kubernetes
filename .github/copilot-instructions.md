# AluraFood Microservices Architecture Guide

## System Overview
This is a Spring Boot 2.6.7 microservices architecture with 4 services:
- **server** (port 8081): Eureka service discovery server
- **gateway** (port 8082): API Gateway using Spring Cloud Gateway
- **pedidos** (dynamic port): Orders microservice with database persistence
- **pagamentos** (dynamic port): Payments microservice with Feign client integration

## Architecture & Data Flows

### Service Discovery & Routing
- **Eureka Server**: `server/ServerApplication.java` - enables service registry at `http://localhost:8081/eureka`
- **Gateway**: Routes all requests through `spring.cloud.gateway.discovery.locator.enabled=true` with lowercase service ID resolution
- **Dynamic Ports**: `pedidos` and `pagamentos` use `server.port=0` (auto-assigned) to support multiple instances with Eureka `instance-id=${spring.application.name}:${random.int}`

### Service Integration
**Pagamentos → Pedidos Communication**:
- Uses OpenFeign (`@EnableFeignClients` in `PagamentosApplication.java`)
- `PedidoClient` interface with `@FeignClient("pedidos-ms")` calls `PUT /pedidos/{id}/pago` to update order status
- Circuit breaker pattern: `@CircuitBreaker(name = "atualizaPedido")` with fallback method `pagamentoAutorizadoComIntegracaoPendente()` when service unavailable
- Config in `application.properties`: sliding window=3, min calls=2, open state=50s

## Project Structure & Patterns

### Common Package Layout (All services except gateway)
```
src/main/java/br/com/alurafood/{service}/
├── {Service}Application.java          // Entry point with @SpringBootApplication
├── config/Configuracao.java           // @Configuration with ModelMapper bean
├── controller/                        // REST endpoints (@RestController)
├── service/                           // Business logic (@Service)
├── model/                             // JPA entities, enums
├── dto/                               // Data Transfer Objects
├── repository/                        // Spring Data JPA interfaces
└── http/                             // (Pagamentos only) Feign clients
src/main/resources/
├── application.properties             // Configuration with DB_HOST/DB_USER/DB_PASSWORD env vars
└── db/migration/                      // Flyway SQL migration scripts (V1__, V2__, etc.)
```

### Key Patterns & Conventions

**DTOs & Mapping**:
- All services use ModelMapper bean: `modelMapper.map(entity, DtoClass.class)`
- DTOs have `@Getter`, `@Setter`, `@NoArgsConstructor`, `@AllArgsConstructor` (Lombok)
- Entity-DTO mapping in services, never return entities directly

**JPA Models**:
- Use `@Entity`, `@Table(name="...")`, ID with `@GeneratedValue(strategy=GenerationType.IDENTITY)`
- Relationships with `@OneToMany(cascade=CascadeType.PERSIST)` and `@ManyToOne(optional=false)`
- Enums mapped with `@Enumerated(EnumType.STRING)` (stored as text, not ordinals)
- Validation: `@NotNull`, `@NotBlank`, `@Positive`, `@Size` annotations

**Repositories**:
- Extend `JpaRepository<Entity, Long>` with custom `@Query` methods
- Use `@Modifying(clearAutomatically=true)` for update operations with `@Transactional`
- Example: `PedidoRepository.atualizaStatus()` and `PedidoRepository.porIdComItens()` with LEFT JOIN FETCH

**Services**:
- Inject dependencies with `@Autowired`, declare final fields with Lombok `@RequiredArgsConstructor`
- Throw `EntityNotFoundException` for missing records (no custom exceptions)
- Service methods are business layer (validation, orchestration)

**Controllers**:
- All endpoints return `ResponseEntity<T>` for proper HTTP status codes
- Use `@PathVariable`, `@RequestBody` with validation `@Valid`
- POST endpoints: `UriComponentsBuilder` for `ResponseEntity.created()`
- Path pattern: `/service-name/{id}/sub-resource` (e.g., `/pedidos/{id}/pago`, `/pagamentos/{id}/confirmar`)

**Pedidos-specific Models**:
- `Pedido`: has `@Enumerated Status` (REALIZADO, CANCELADO, PAGO, CONFIRMADO, PRONTO, ENTREGUE, etc.)
- `ItemDoPedido`: child entity with `@ManyToOne` to Pedido
- Status update pattern: load pedido with items, modify status, call repository update

**Pagamentos-specific Models**:
- `Pagamento`: has `@Enumerated Status` (CRIADO, CONFIRMADO, CONFIRMADO_SEM_INTEGRACAO, CANCELADO)
- Stores both `pedidoId` and `formaDePagamentoId` as Long (no foreign keys - external references)
- Circuit breaker integration: patch endpoint `/pagamentos/{id}/confirmar` with fallback

## Build & Execution

**Building individual services**:
```bash
cd gateway && ./mvnw clean install
cd pedidos && ./mvnw clean install
cd pagamentos && ./mvnw clean install
cd server && ./mvnw clean install
```

**Required Environment Variables** (for pedidos & pagamentos):
```bash
DB_HOST=localhost        # MySQL hostname
DB_USER=root            # Database user
DB_PASSWORD=password    # Database password
```

**Startup Order**:
1. Start `server` first (Eureka registry must be available)
2. Then `pedidos` and `pagamentos` (they register with Eureka)
3. Finally `gateway` (discovers services via Eureka)

**Database Setup**:
- Uses Flyway for migrations (auto-runs on startup)
- Pedidos: migration V1 creates `pedidos`, V2 creates `item_do_pedido`
- Pagamentos: migration V1 creates `pagamentos` table
- Auto-create databases if not exist via `?createDatabaseIfNotExist=true`

## Common Modifications

**Adding an endpoint**:
1. Create DTO in `dto/` with Lombok annotations
2. Add method to `service/` with validation and business logic
3. Add `@GetMapping`/`@PostMapping`/`@PutMapping` to controller returning `ResponseEntity`
4. Use ModelMapper for entity↔DTO conversion

**Connecting to another service**:
1. Create Feign client interface in `http/` folder with `@FeignClient("service-name")`
2. Declare methods matching target endpoints
3. Inject client in service and call via method
4. Add `@EnableFeignClients` to Application.java
5. For resilience, wrap calls in `@CircuitBreaker` with fallback methods

**Database changes**:
1. Create new migration file: `src/main/resources/db/migration/V{N}__description.sql`
2. Follow Flyway naming: prefix `V` + version number + underscores + description
3. Migrations run automatically on startup before Spring context loads

## Environment Context
- Java 17, Maven 3.8.4, Spring Boot 2.6.7, Spring Cloud 2021.0.2
- Database: MySQL (connector `mysql:mysql-connector-java`)
- ORM: Spring Data JPA with Hibernate
- Migration: Flyway
- Service Communication: OpenFeign, Resilience4j Circuit Breaker
- Package structure uses domain-driven package organization: `br.com.alurafood.{service}`
