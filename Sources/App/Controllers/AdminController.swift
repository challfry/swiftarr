import Vapor
import Crypto
import FluentSQL

/// The collection of `/api/v3/admin/*` route endpoints and handler functions related
/// to a user's own data.
///
/// Separating these from the endpoints related to users in general helps make for a
/// cleaner collection, since use of `User.parameter` in the paths here can be avoided
/// entirely.

struct AdminController: RouteCollection {
    
	var twarrtIDParam = PathComponent(":twarrt_id")
	let forumIDParam = PathComponent(":forum_id")
	let postIDParam = PathComponent(":post_id")
	let modStateParam = PathComponent(":mod_state")

// MARK: RouteCollection Conformance

	/// Required. Registers routes to the incoming router.
	func boot(routes: RoutesBuilder) throws {
		
		// convenience route group for all /api/v3/admin endpoints
		let adminRoutes = routes.grouped("api", "v3", "admin")
		
		// instantiate authentication middleware
		let tokenAuthMiddleware = Token.authenticator()
//		let requireVerifiedMiddleware = RequireVerifiedMiddleware()
		let requireModMiddleware = RequireModeratorMiddleware()
		let guardAuthMiddleware = User.guardMiddleware()
		
		// set protected route groups
//		let userAuthGroup = adminRoutes.grouped([tokenAuthMiddleware, guardAuthMiddleware, requireVerifiedMiddleware])
		let moderatorAuthGroup = adminRoutes.grouped([tokenAuthMiddleware, guardAuthMiddleware, requireModMiddleware])
				 
		// endpoints available for Moderators only
		moderatorAuthGroup.get("reports", use: reportsHandler)
		moderatorAuthGroup.post("reports", ":report_id", "handleall", use: beginProcessingReportsHandler)
		moderatorAuthGroup.post("reports", ":report_id", "closeall", use: closeReportsHandler)
		moderatorAuthGroup.get("moderationlog", use: moderatorActionLogHandler)

		moderatorAuthGroup.get("twarrt", twarrtIDParam, use: twarrtModerationHandler)
		moderatorAuthGroup.post("twarrt", twarrtIDParam, "setstate", modStateParam, use: twarrtSetModerationStateHandler)
		
		moderatorAuthGroup.get("forumpost", postIDParam, use: forumPostModerationHandler)
		moderatorAuthGroup.post("forumpost", postIDParam, "setstate", modStateParam, use: forumPostSetModerationStateHandler)
		
		moderatorAuthGroup.get("forum", forumIDParam, use: forumModerationHandler)
		moderatorAuthGroup.post("forum", forumIDParam, "setstate", modStateParam, use: forumSetModerationStateHandler)



//        tokenAuthGroup.get("user", ":user_id", use: userHandler)
	}
    
    // MARK: - Open Access Handlers
    
    
    // MARK: - basicAuthGroup Handlers (not logged in)
    // All handlers in this route group require a valid HTTP Basic Authentication
    // header in the request.
    

    // MARK: - tokenAuthGroup Handlers (logged in)
    // All handlers in this route group require a valid HTTP Bearer Authentication
    // header in the request.
    
    /// `GET /api/v3/admin/user/ID`
    ///
    /// Retrieves the full `User` model of the specified user.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 403 error if the user is not an admin.
    /// - Returns: `User`.
    func userHandler(_ req: Request) throws -> EventLoopFuture<User> {
        let user = try req.auth.require(User.self)
        guard user.accessLevel.hasAccess(.admin) else {
            throw Abort(.forbidden, reason: "admins only")
        }
        return User.findFromParameter("user_id", on: req)
    }
    
    /// `GET /api/v3/admin/reports`
    ///
    /// Retrieves the full `Report` model of all reports.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 403 error if the user is not an admin.
    /// - Returns: `[Report]`.
    func reportsHandler(_ req: Request) throws -> EventLoopFuture<[ReportAdminData]> {
        let user = try req.auth.require(User.self)
        guard user.accessLevel.hasAccess(.moderator) else {
            throw Abort(.forbidden, reason: "Moderators only")
        }
        return Report.query(on: req.db).sort(\.$createdAt, .descending).all().flatMapThrowing { reports in
        	return try reports.map { try ReportAdminData.init(req: req, report: $0) }
        }
    }
    
    /// `POST /api/v3/admin/reports/ID/handleall`
    /// 
    /// This call is how a Moderator can take a user Report off the queue and begin handling it. More correctly, it takes all user reports referring to the same
	/// piece of content and marks them all handled at once.
	/// 
	/// Moving reports through the 'handling' state is not necessary--you can go straight to 'closed'--but this marks the reports as being 'taken' by the given mod
	/// so other mods can avoid duplicate or conflicting work. Also, any ModeratorActions taken while a mod has reports in the 'handling' state get tagged with an
	/// identifier that matches the actions to the reports. Reports should be closed once a mod is done with them.
    func beginProcessingReportsHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
// TODO: This could benefit from checks that the mod doesn't currently have an actionGroup (that is, already handling a report)
// and that the reports aren't already being handled by another mod. But, need to think about process--don't want reports getting stuck.
        let user = try req.auth.require(User.self)
        guard user.accessLevel.hasAccess(.moderator) else {
            throw Abort(.forbidden, reason: "Moderators only")
        }
        return Report.findFromParameter("report_id", on: req).flatMap { report in
        	return Report.query(on: req.db)
        			.filter(\.$reportType == report.reportType)
        			.filter(\.$reportedID == report.reportedID)
        			.filter(\.$isClosed == false)
        			.all()
        			.throwingFlatMap { reports in
				let groupID = UUID()
				var futures: [EventLoopFuture<Void>] = try reports.map { 
        			$0.$handledBy.id = try user.requireID()
        			$0.actionGroup = groupID
        			return $0.save(on: req.db)
				}
 				user.actionGroup = groupID
				futures.append(user.save(on: req.db))
 				return futures.flatten(on: req.eventLoop).transform(to: .ok)
			}
		}
    }
    
    /// `POST /api/v3/admin/reports/ID/closeall`
    ///
    /// Closes all reports filed against the same piece of content as the given report.
    func closeReportsHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
        guard user.accessLevel.hasAccess(.moderator) else {
            throw Abort(.forbidden, reason: "Moderators only")
        }
        return Report.findFromParameter("report_id", on: req).flatMap { report in
        	return Report.query(on: req.db)
        			.filter(\.$reportType == report.reportType)
        			.filter(\.$reportedID == report.reportedID)
        			.filter(\.$isClosed == false)
        			.all()
        			.throwingFlatMap { reports in
				var futures: [EventLoopFuture<Void>] = reports.map { 
					$0.isClosed = true
        			return $0.save(on: req.db)
				}
				user.actionGroup = nil
 				futures.append(user.save(on: req.db))
 				return futures.flatten(on: req.eventLoop).transform(to: .ok)
			}
		}
    }
    
    /// `GET /api/v3/admin/moderationlog`
    ///
    /// Retrieves ModeratorAction recoreds. These records are a log of Mods using their Mod powers.
	/// 
	/// URL Query Parameters:
	/// * `?start=INT` - the offset from the anchor to start. Offset only counts twarrts that pass the filters.
    /// * `?limit=INT` - the maximum number of twarrts to retrieve: 1-200, default is 50
    /// 
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 403 error if the user is not an admin.
    /// - Returns: `[Report]`.
    func moderatorActionLogHandler(_ req: Request) throws -> EventLoopFuture<[ModeratorActionLogData]> {
        let start = (req.query[Int.self, at: "start"] ?? 0)
        let limit = (req.query[Int.self, at: "limit"] ?? 50).clamped(to: 0...200)
    	return ModeratorAction.query(on: req.db)
				.range(start..<(start + limit))
    			.sort(\.$createdAt, .descending).all().flatMapThrowing { logEntries in
    		let result = try logEntries.map { try ModeratorActionLogData(action: $0, on: req) }
    		return result
    	}
    }
    
	/// Moderator only. Returns info admins and moderators need to review a twarrt. Works if twarrt has been deleted. Shows
	/// twarrt's quarantine and reviewed states.
    ///
    /// * The current Twarrt
    /// * Previous versions of the twarrt
    /// * Reports against the twarrt
    func twarrtModerationHandler(_ req: Request) throws -> EventLoopFuture<TwarrtModerationData> {
  		guard let paramVal = req.parameters.get(twarrtIDParam.paramString), let twarrtID = Int(paramVal) else {
            throw Abort(.badRequest, reason: "Request parameter \(twarrtIDParam.paramString) is missing.")
        }
		return Twarrt.query(on: req.db).filter(\._$id == twarrtID).withDeleted().first()
        		.unwrap(or: Abort(.notFound, reason: "no value found for identifier '\(paramVal)'")).flatMap { twarrt in
   			return Report.query(on: req.db)
   					.filter(\.$reportType == .twarrt)
   					.filter(\.$reportedID == paramVal)
   					.sort(\.$createdAt, .descending).all().flatMap { reports in
				return twarrt.$edits.query(on: req.db).sort(\.$createdAt, .ascending).all().flatMapThrowing { edits in
					let authorHeader = try req.userCache.getHeader(twarrt.$author.id)
					let twarrtData = try TwarrtData(twarrt: twarrt, creator: authorHeader, isBookmarked: false, 
							userLike: nil, likeCount: 0, overrideQuarantine: true)
					let editData: [PostEditLogData] = try edits.map {
						let editAuthorHeader = try req.userCache.getHeader($0.$editor.id)
						return try PostEditLogData(edit: $0, editor: editAuthorHeader)
					}
					let reportData = try reports.map { try ReportAdminData.init(req: req, report: $0) }
					let modData = TwarrtModerationData(twarrt: twarrtData, isDeleted: twarrt.deletedAt != nil, 
							moderationStatus: twarrt.moderationStatus, edits: editData, reports: reportData)
					return modData
				}
			}
        }
	}
	
    func twarrtSetModerationStateHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
  		guard let modState = req.parameters.get(modStateParam.paramString) else {
            throw Abort(.badRequest, reason: "Request parameter `Moderation_State` is missing.")
        }
        return Twarrt.findFromParameter(twarrtIDParam, on: req).throwingFlatMap { twarrt in
        	try twarrt.moderationStatus.setFromParameterString(modState)
			twarrt.logIfModeratorAction(ModeratorActionType.setFromModerationStatus(twarrt.moderationStatus), user: user, on: req)
        	return twarrt.save(on: req.db).transform(to: .ok)
        }
    }
	
	/// Moderator only. Returns info admins and moderators need to review a forumPost. Works if forumPost has been deleted. Shows
	/// forumPost's quarantine and reviewed states.
    ///
    /// * The current forumPost
    /// * Previous versions of the forumPost
    /// * Reports against the forumPost
    func forumPostModerationHandler(_ req: Request) throws -> EventLoopFuture<ForumPostModerationData> {
  		guard let paramVal = req.parameters.get(postIDParam.paramString), let postID = Int(paramVal) else {
            throw Abort(.badRequest, reason: "Request parameter \(postIDParam.paramString) is missing.")
        }
		return ForumPost.query(on: req.db).filter(\._$id == postID).withDeleted().first()
        		.unwrap(or: Abort(.notFound, reason: "no value found for identifier '\(paramVal)'")).flatMap { post in
   			return Report.query(on: req.db)
   					.filter(\.$reportType == .forumPost)
   					.filter(\.$reportedID == paramVal)
   					.sort(\.$createdAt, .descending).all().flatMap { reports in
				return post.$edits.query(on: req.db).sort(\.$createdAt, .ascending).all().flatMapThrowing { edits in
					let authorHeader = try req.userCache.getHeader(post.$author.id)
					let postData = try PostDetailData(post: post, author: authorHeader, overrideQuarantine: true)
					let editData: [PostEditLogData] = try edits.map {
						let editAuthorHeader = try req.userCache.getHeader($0.$editor.id)
						return try PostEditLogData(edit: $0, editor: editAuthorHeader)
					}
					let reportData = try reports.map { try ReportAdminData.init(req: req, report: $0) }
					let modData = ForumPostModerationData(forumPost: postData, isDeleted: post.deletedAt != nil, 
							moderationStatus: post.moderationStatus, edits: editData, reports: reportData)
					return modData
				}
			}
        }
	}
    
    func forumPostSetModerationStateHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
  		guard let modState = req.parameters.get(modStateParam.paramString) else {
            throw Abort(.badRequest, reason: "Request parameter `Moderation_State` is missing.")
        }
        return ForumPost.findFromParameter(postIDParam, on: req).throwingFlatMap { forumPost in
        	try forumPost.moderationStatus.setFromParameterString(modState)
			forumPost.logIfModeratorAction(ModeratorActionType.setFromModerationStatus(forumPost.moderationStatus), user: user, on: req)
        	return forumPost.save(on: req.db).transform(to: .ok)
        }
    }

	/// Moderator only. Returns info admins and moderators need to review a forumPost. Works if forumPost has been deleted. Shows
	/// forumPost's quarantine and reviewed states.
    ///
    /// * The current forumPost
    /// * Previous versions of the forumPost
    /// * Reports against the forumPost
    func forumModerationHandler(_ req: Request) throws -> EventLoopFuture<ForumModerationData> {
		guard let forumIDString = req.parameters.get(forumIDParam.paramString), let forumID = UUID(forumIDString) else {
            throw Abort(.badRequest, reason: "Request parameter \(forumIDParam.paramString) is missing.")
        }
		return Forum.query(on: req.db).filter(\.$id == forumID).withDeleted().first()
        		.unwrap(or: Abort(.notFound, reason: "no value found for identifier '\(forumID)'")).flatMap { forum in
   			return Report.query(on: req.db)
   					.filter(\.$reportType == .forum)
   					.filter(\.$reportedID == forumIDString)
   					.sort(\.$createdAt, .descending).all().flatMap { reports in
				return forum.$edits.query(on: req.db).sort(\.$createdAt, .ascending).all().flatMapThrowing { edits in
					let forumData = try ForumAdminData(forum, on: req)
					let editData: [ForumEditLogData] = try edits.map {
						return try ForumEditLogData($0, on: req)
					}
					let reportData = try reports.map { try ReportAdminData.init(req: req, report: $0) }
					let modData = ForumModerationData(forum: forumData, isDeleted: forum.deletedAt != nil, 
							moderationStatus: forum.moderationStatus, edits: editData, reports: reportData)
					return modData
				}
			}
        }
	}
    
    func forumSetModerationStateHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
  		guard let modState = req.parameters.get(modStateParam.paramString) else {
            throw Abort(.badRequest, reason: "Request parameter `Moderation_State` is missing.")
        }
        return Forum.findFromParameter(forumIDParam, on: req).throwingFlatMap { forum in
        	try forum.moderationStatus.setFromParameterString(modState)
			forum.logIfModeratorAction(ModeratorActionType.setFromModerationStatus(forum.moderationStatus), user: user, on: req)
        	return forum.save(on: req.db).transform(to: .ok)
        }
    }

	
    // MARK: - Helper Functions

}
