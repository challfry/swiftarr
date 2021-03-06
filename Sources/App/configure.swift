import Vapor
import Redis
import Fluent
import FluentPostgresDriver
import Leaf

/// Called before your application initializes. Calls several other config methos do its work. Sub functions are only
/// here for easier organization. If order-of-initialization issues arise, rearrange as necessary.
public func configure(_ app: Application) throws {
    
    // use iso8601ms for dates
    let jsonEncoder = JSONEncoder()
    let jsonDecoder = JSONDecoder()
    if #available(OSX 10.13, *) {
        jsonEncoder.dateEncodingStrategy = .iso8601ms
        jsonDecoder.dateDecodingStrategy = .iso8601ms
    } else {
        // Fallback on earlier versions
    }
	ContentConfiguration.global.use(encoder: jsonEncoder, for: .json)
    ContentConfiguration.global.use(decoder: jsonDecoder, for: .json)

	try configureSettings(app)
	try HTTPServerConfiguration(app)
	try databaseConnectionConfiguration(app)
	try configureMiddleware(app)
	try configureSessions(app)
	try configureLeaf(app)
    try routes(app)
	try configureMigrations(app)

	// Add lifecycle handlers 
	app.lifecycle.use(Application.UserCacheStartup())

}

func configureSettings(_ app: Application) throws {
	if app.environment == .testing {
		// Until we get a proper 2022 schedule, we're using the 2020 schedule for testing. 
		Settings.shared.cruiseStartDate = Calendar.autoupdatingCurrent.date(from: DateComponents(calendar: Calendar.current, 
			timeZone: TimeZone(abbreviation: "EST")!, year: 2020, month: 3, day: 7))!
	}
	else if app.environment == .development {
		Logger(label: "app.swiftarr.configuration") .info("Starting up in Development mode.")
	}
}

func HTTPServerConfiguration(_ app: Application) throws {
	// run API on port 8081 by default and set a 10MB hard limit on file size
    let port = Int(Environment.get("PORT") ?? "8081")!
	app.http.server.configuration.port = port
	app.routes.defaultMaxBodySize = "10mb"
	
	// for testing
	if app.environment == .development {
		app.http.server.configuration.hostname = "192.168.0.19"
	}
	else if app.environment == .production {
		app.http.server.configuration.hostname = "joco.hollandamerica.com"
	}
}

func databaseConnectionConfiguration(_ app: Application) throws {
	// configure PostgreSQL connection
    // note: environment variable nomenclature is vapor.cloud compatible
    // support for Heroku environment
    if let postgresURL = Environment.get("DATABASE_URL") {
		try app.databases.use(.postgres(url: postgresURL), as: .psql)
    } else 
    {
        // otherwise
        let postgresHostname = Environment.get("DATABASE_HOSTNAME") ?? "localhost"
        let postgresUser = Environment.get("DATABASE_USER") ?? "swiftarr"
        let postgresPassword = Environment.get("DATABASE_PASSWORD") ?? "password"
        let postgresDB: String
        let postgresPort: Int
        if app.environment == .testing {
            postgresDB = "swiftarr-test"
            postgresPort = Int(Environment.get("DATABASE_PORT") ?? "5433")!
        } else {
            postgresDB = Environment.get("DATABASE_DB") ?? "swiftarr"
            postgresPort = 5432
        }
		app.databases.use(.postgres(hostname: postgresHostname, port: postgresPort, username: postgresUser, 
				password: postgresPassword, database: postgresDB), as: .psql)
    }
    
    // configure Redis connection
    // support for Heroku environment
    if let redisString = Environment.get("REDIS_URL"), let redisURL = URL(string: redisString) {
		app.redis.configuration = try RedisConfiguration(url: redisURL)
    } else 
    {
        // otherwise
        let redisHostname = Environment.get("REDIS_HOSTNAME") ?? "localhost"
        let redisPort = (app.environment == .testing) ? Int(Environment.get("REDIS_PORT") ?? "6380")! : 6379
		app.redis.configuration = try RedisConfiguration(hostname: redisHostname, port: redisPort)
    }

}

func configureMiddleware(_ app: Application) throws {
	// register middleware
//    app.middleware.use(FileMiddleware(publicDirectory: "Public/")) // serves files from `Public/` directory
//	app.middleware.use(SwiftarrErrorMiddleware.default(environment: app.environment))
	var new = Middlewares()
	new.use(RouteLoggingMiddleware(logLevel: .info))
	new.use(SwiftarrErrorMiddleware.default(environment: app.environment))
	new.use(FileMiddleware(publicDirectory: "Resources/Assets")) // serves files from `Public/` directory
	app.middleware = new
}

func configureSessions(_ app: Application) throws {
	app.sessions.configuration.cookieName = "swiftarr_session"
	
	// Configures cookie value creation.
	app.sessions.configuration.cookieFactory = { sessionID in
		.init(string: sessionID.string,
				expires: Date( timeIntervalSinceNow: 60 * 60 * 24 * 7),
				maxAge: nil,
				domain: nil,
				path: "/",
				isSecure: false,
				isHTTPOnly: true,
				sameSite: .lax
		)
	}
	
	// .memory is the default, but we'll eventually want to use Redis to store sessions.
//	app.sessions.use(.redis)
}

func configureLeaf(_ app: Application) throws {
    app.views.use(.leaf)
    
    // Custom Leaf tags
    app.leaf.tags["elem"] = ElementSanitizerTag()
    app.leaf.tags["addJocomoji"] = AddJocomojiTag()
    app.leaf.tags["relativeTime"] = RelativeTimeTag()
    app.leaf.tags["eventTime"] = EventTimeTag()
    app.leaf.tags["avatar"] = AvatarTag()
}
	
func configureMigrations(_ app: Application) throws {

	// Migration order is important here, particularly for initializing a new database.
	// First initialize custom enum types. These are custom 'types' for fields (like .string, .int, or .uuid) -- but custom.
	app.migrations.add(CreateCustomEnums(), to: .psql) 
	
	// Second group is schema-creation migrations. These create an initial database schema
	// and do not add any data to the db. These need to be ordered such that referred-to tables
	// come before referrers.
	app.migrations.add(CreateUserSchema(), to: .psql)
	app.migrations.add(CreateTokenSchema(), to: .psql)
	app.migrations.add(CreateRegistrationCodeSchema(), to: .psql)
	app.migrations.add(CreateProfileEditSchema(), to: .psql)
	app.migrations.add(CreateUserNoteSchema(), to: .psql)
	app.migrations.add(CreateModeratorActionSchema(), to: .psql)
	app.migrations.add(CreateBarrelSchema(), to: .psql)
	app.migrations.add(CreateReportSchema(), to: .psql)
	app.migrations.add(CreateCategorySchema(), to: .psql)
	app.migrations.add(CreateForumSchema(), to: .psql)
	app.migrations.add(CreateForumEditSchema(), to: .psql)
	app.migrations.add(CreateForumPostSchema(), to: .psql)
	app.migrations.add(CreateForumPostEditSchema(), to: .psql)
	app.migrations.add(CreateForumReadersSchema(), to: .psql)
	app.migrations.add(CreatePostLikesSchema(), to: .psql)
	app.migrations.add(CreateEventSchema(), to: .psql)
	app.migrations.add(CreateTwarrtSchema(), to: .psql)
	app.migrations.add(CreateTwarrtEditSchema(), to: .psql)
	app.migrations.add(CreateTwarrtLikesSchema(), to: .psql)
	app.migrations.add(CreateFriendlyFezSchema(), to: .psql)
	app.migrations.add(CreateFezParticipantSchema(), to: .psql)
	app.migrations.add(CreateFezPostSchema(), to: .psql)
	
	// Third, migrations that seed the db with initial data
	app.migrations.add(CreateAdminUser(), to: .psql)
	app.migrations.add(CreateClientUsers(), to: .psql)
	app.migrations.add(CreateRegistrationCodes(), to: .psql)
	app.migrations.add(CreateEvents(), to: .psql)
	app.migrations.add(CreateCategories(), to: .psql)
//y	app.migrations.add(CreateForums(), to: .psql)
	app.migrations.add(CreateEventForums(), to: .psql)
	if (app.environment == .testing || app.environment == .development) {
		app.migrations.add(CreateTestUsers(), to: .psql)
		app.migrations.add(CreateTestData(), to: .psql)
	}
	
	// Fourth, migrations that touch up initial state
	app.migrations.add(SetInitialCategoryForumCounts(), to: .psql)
}
    
    // add Fluent commands for CLI migration and revert
//    var commandConfig = CommandConfig.default()
//    commandConfig.useFluentCommands()
//    services.register(commandConfig)

