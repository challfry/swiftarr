import FluentPostgreSQL
import Vapor
import Authentication
import Redis

/// Called before your application initializes.
public func configure(_ config: inout Config, _ env: inout Environment, _ services: inout Services) throws {

    /// run API on port 8081 by default and set a 10MB hard limit on file size
    services.register {
        container -> NIOServerConfig in
        .default(port: 8081, maxBodySize: 10_000_000)
    }

    /// register providers first
    try services.register(FluentPostgreSQLProvider())
    try services.register(AuthenticationProvider())
    try services.register(RedisProvider())

    /// register routes to the router
    let router = EngineRouter.default()
    try routes(router)
    services.register(router, as: Router.self)

    /// register middleware
    var middlewares = MiddlewareConfig()
    // middlewares.use(FileMiddleware.self) // serves files from `Public/` directory
    middlewares.use(ErrorMiddleware.self) // catches errors and converts to HTTP response
    services.register(middlewares)

    /// configure PostgreSQL connection
    let postgresHost = Environment.get("DATABASE_HOST") ?? "localhost"
    let postgresUser = Environment.get("DATABASE_USER") ?? "swiftarr"
    let postgresPassword = Environment.get("DATABASE_PASSWORD") ?? "password"
    let postgresDB: String
    let postgresPort: Int
    if (env == .testing) {
        postgresDB = "swiftarr-test"
        postgresPort = Int(Environment.get("DATABASE_PORT") ?? "5433")!
    } else {
        postgresDB = Environment.get("DATABASE_DB") ?? "swiftarr"
        postgresPort = 5432
    }
    let postgresConfig = PostgreSQLDatabaseConfig(
        hostname: postgresHost,
        port: postgresPort,
        username: postgresUser,
        database: postgresDB,
        password: postgresPassword,
        transport: .cleartext
    )
    let postgres = PostgreSQLDatabase(config: postgresConfig)
    
    /// configure Redis connection
    var redisConfig = RedisClientConfig()
    let redisHost: String
    let redisPort: Int
    if (env == .testing) {
        redisHost = Environment.get("REDIS_HOST") ?? "localhost"
        redisPort = Int(Environment.get("REDIS_PORT") ?? "6380")!
    } else {
        redisHost = Environment.get("REDIS_HOST") ?? "localhost"
        redisPort = 6379
    }
    redisConfig.hostname = redisHost
    redisConfig.port = redisPort
    let redis = try RedisDatabase(config: redisConfig)
    
    /// register databases
    var databases = DatabasesConfig()
    services.register(databases)

    /// configure migrations
    var migrations = MigrationConfig()
    services.register(migrations)
}
