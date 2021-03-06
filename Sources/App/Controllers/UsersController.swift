import Vapor
import Crypto
import FluentSQL
import Fluent
import Redis
import RediStack

/// The collection of `/api/v3/user/*` route endpoints and handler functions related
/// to a user's own data.
///
/// Separating these from the endpoints related to users in general helps make for a
/// cleaner collection, since use of `User.parameter` in the paths here can be avoided
/// entirely.

struct UsersController: RouteCollection {
    
    // Vapor uses ":pathParam" to declare a parameterized path element, and "pathParam" (no colon) to get 
    // the parameter value in route handlers. findFromParameter() has a variant that takes a PathComponent,
    // and it's slightly more type-safe to do this rather than relying on string matching.
    var userIDParam = PathComponent(":user_id")
    var searchStringParam = PathComponent(":search_string")

// MARK: RouteCollection Conformance
    
    /// Required. Registers routes to the incoming router.
    func boot(routes: RoutesBuilder) throws {
        
        // convenience route group for all /api/v3/users endpoints
        let usersRoutes = routes.grouped("api", "v3", "users")
        
        // instantiate authentication middleware
        let basicAuthMiddleware = User.authenticator()
        let guardAuthMiddleware = User.guardMiddleware()
        let tokenAuthMiddleware = Token.authenticator()
        
        // set protected route groups
        let sharedAuthGroup = usersRoutes.grouped([basicAuthMiddleware, tokenAuthMiddleware, guardAuthMiddleware])
        let tokenAuthGroup = usersRoutes.grouped([tokenAuthMiddleware, guardAuthMiddleware])
        
        // open access endpoints
        
        // endpoints available only when not logged in
        
        // endpoints available whether logged in or out
        sharedAuthGroup.get("find", ":userSearchString", use: findHandler)
        sharedAuthGroup.get(userIDParam, "profile", use: profileHandler)
        sharedAuthGroup.get(userIDParam, use: headerHandler)

        // endpoints available only when logged in
        tokenAuthGroup.post(userIDParam, "block", use: blockHandler)
        tokenAuthGroup.get("match", "allnames", searchStringParam, use: matchAllNamesHandler)
        tokenAuthGroup.get("match", "username", searchStringParam, use: matchUsernameHandler)
        tokenAuthGroup.post(userIDParam, "mute", use: muteHandler)
        tokenAuthGroup.post(userIDParam, "note", use: noteCreateHandler)
        tokenAuthGroup.post(userIDParam, "note", "delete", use: noteDeleteHandler)
        tokenAuthGroup.delete(userIDParam, "note", use: noteDeleteHandler)
        tokenAuthGroup.get(userIDParam, "note", use: noteHandler)
        tokenAuthGroup.post(userIDParam, "report", use: reportHandler)
        tokenAuthGroup.post(userIDParam, "unblock", use: unblockHandler)
        tokenAuthGroup.post(userIDParam, "unmute", use: unmuteHandler)
    }
    
    // MARK: - Open Access Handlers
    
    // MARK: - basicAuthGroup Handlers (not logged in)
    // All handlers in this route group require a valid HTTP Basic Authentication
    // header in the request.
    
    // MARK: - sharedAuthGroup Handlers (logged in or not)
    // All handlers in this route group require a valid HTTP Basic Authorization
    // *or* HTTP Bearer Authorization header in the request.
    
    /// `GET /api/v3/users/find/STRING`
    ///
    /// Retrieves a user's `UserHeader` using either an ID (UUID string) or a username.
    ///
    /// This endpoint is of limited utility, but is included for the case of obtaining a
    /// user's ID from a username. If you have an ID and want the associated username, use
    /// the more efficient `/api/v3/users/ID` endpoint instead.
    ///
    /// - Note: Because a username can be changed, there is no guarantee that a once-valid
    ///   username will result in a successful return, even though the User itself does
    ///   exist.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 404 error if no match is found.
    /// - Returns: `UserHeader` containing the user's ID, username and timestamp of last
    ///   profile update.
    func findHandler(_ req: Request) throws -> UserHeader {
        let requester = try req.auth.require(User.self)
        let requesterID = try requester.requireID()
		guard let parameter = req.parameters.get("userSearchString") else {
			throw Abort(.badRequest, reason: "Find User: missing search string")
		}
		var userHeader: UserHeader? = req.userCache.getHeader(parameter) 
        // try converting to UUID
		if userHeader == nil, let userID = UUID(uuidString: parameter) {
			userHeader = try? req.userCache.getHeader(userID)
		}
		guard let foundUser = userHeader else {
			throw Abort(.notFound, reason: "no user found for identifier '\(parameter)'")
		}
		let blocked = req.userCache.getBlocks(requesterID)
		if blocked.contains(foundUser.userID) {
			throw Abort(.notFound, reason: "no user found for identifier '\(parameter)'")
		}
		return foundUser
	}
            
    /// `GET /api/v3/users/ID`
    ///
    /// Retrieves the specified user's `UserHeader` info.
    ///
    /// This endpoint provides one-off retrieval of the user information appropriate for
    /// a header on posted content – the user's ID, current generated `.displayedName`, and
    /// filename of their current profile image.
    ///
    /// For bulk data retrieval, see the `ClientController` endpoints.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: `UserHeader` containing the user's ID, `.displayedName` and profile
    ///   image filename.
    func headerHandler(_ req: Request) throws -> UserHeader {
        let requester = try req.auth.require(User.self)
		guard let parameter = req.parameters.get(userIDParam.paramString) else {
			throw Abort(.badRequest, reason: "UserID parameter missing")
		}
		guard let userHeader = req.userCache.getHeader(parameter), 
				try !req.userCache.getBlocks(requester.requireID()).contains(userHeader.userID) else {
			throw Abort(.notFound, reason: "no user found for identifier '\(parameter)'")
		}
		return userHeader
    }
    
    /// `GET /api/v3/users/ID/profile`
    ///
    /// Retrieves the specified user's profile, as a `ProfilePublicData` object.
    ///
    /// This endpoint can be reached with either Basic or Bearer authenticaton. If using Basic
    /// (requesting user is *not* logged in), the data returned may be a limited subset if the
    /// profile user's `.limitAccess` setting is `true`, and the `.message` field will contain
    /// text to inform the viewing user of that fact.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 404 error if the profile is not available. A 5xx response should be reported
    ///   as a likely bug, please and thank you.
    /// - Returns: `ProfilePublicData` containing the displayable properties of the specified
    ///   user's profile.
    func profileHandler(_ req: Request) throws -> EventLoopFuture<ProfilePublicData> {
        let requester = try req.auth.require(User.self)
        return User.findFromParameter(userIDParam, on: req)
			.throwingFlatMap { (profiledUser) in
				// 404 if blocked
        		let blocked = try req.userCache.getBlocks(requester)
				if blocked.contains(try profiledUser.requireID()) {
					throw Abort(.notFound, reason: "profile is not available")
				}
				// a .banned profile is only available to .moderator or above
				if profiledUser.accessLevel == .banned && !requester.accessLevel.hasAccess(.moderator) {
					throw Abort(.notFound, reason: "profile is not available")
				}
				var publicProfile = try ProfilePublicData(user: profiledUser, note: nil)
				// if auth type is Basic, requester is not logged in, so hide info if
				// `.limitAccess` is true or requester is .banned
				if (req.headers.basicAuthorization != nil && profiledUser.limitAccess) || requester.accessLevel == .banned {
					publicProfile.about = ""
					publicProfile.email = ""
					publicProfile.homeLocation = ""
					publicProfile.message = "You must be logged in to view this user's Profile details."
					publicProfile.preferredPronoun = ""
					publicProfile.realName = ""
					publicProfile.roomNumber = ""
				}
				// include UserNote if any, then return
				return try requester.$notes.query(on: req.db)
					.filter(\.$noteSubject.$id == profiledUser.requireID())
					.first()
					.map { (note) in
						if let note = note {
							publicProfile.note = note.note
						}
						return publicProfile
				}
		}
    }
        
    // MARK: - tokenAuthGroup Handlers (logged in)
    // All handlers in this route group require a valid HTTP Bearer Authentication
    // header in the request.
    
    /// `POST /api/v3/users/ID/block`
    ///
    /// Blocks the specified `User`. The blocking user and any sub-accounts will not be able
    /// to see posts from the blocked `User` or any of their associated sub-accounts, and vice
    /// versa. This affects all forms of communication, public and private, as well as user
    /// searches.
    ///
    /// Only the specified user is added to the block list, so as not to explicitly expose the
    /// ownership of any other accounts the blocked user may be using. The blocking of any
    /// associated user accounts is handled under the hood.
    ///
    /// Users with an `.accessLevel` of `.moderator` or higher may not be blocked. A block
    /// applied to such accounts will be accepted, but is effectively a uni-directional block.
    /// That is, the blocking user will not see the blocked user, but the blocked privileged
    /// user will still see the blocking user throughout the public areas of the system, and
    /// their role accounts will still be visible to the blocking user.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: 201 Created on success.
    func blockHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let requester = try req.auth.require(User.self)
		// get requester block barrel
        let blockBarrel = try Barrel.query(on: req.db)
					.filter(\.$ownerID == requester.requireID())
					.filter(\.$barrelType == .userBlock)
					.first()
					.unwrap(or: Abort(.internalServerError, reason: "userBlock barrel not found"))
        return User.findFromParameter(userIDParam, on: req)
        	.and(blockBarrel)
            .flatMap { (user, barrel) in
				do {
					// add blocked user to barrel
					barrel.modelUUIDs.append(try user.requireID())
					return barrel.save(on: req.db).flatMap { (_) in
						do {
							// update cache and return 201
							return try self.setBlocksCache(by: requester, of: user, on: req)
								.transform(to: .created)
						}
						catch {
							return req.eventLoop.makeFailedFuture(error)
						}
					}
				}
				catch {
					return req.eventLoop.makeFailedFuture(error)
				}
			}
    }
    
    /// `GET /api/v3/users/match/allnames/STRING`
    ///
    /// Retrieves all `User.userSearch` values containing the specified substring,
    /// returning an array of `UserHeader` structs..
    /// The intended use for this endpoint is to help isolate a particular user in an
    /// auto-complete type scenario, by searching **all** of the `.displayName`, `.username`
    /// and `.realName` profile fields.
    ///
    /// Compare to `/api/v3/user/match/username/STRING`, which searches just `.username` and
    /// returns an array of just strings.
    ///
    /// - Note: If the search substring contains "unsafe" characters, they must be url encoded.
    ///   Unicode characters are supported. A substring comprised only of whitespace is
    ///   disallowed. A substring of "@" or "(@" is explicitly disallowed to prevent single-step
    ///   username harvesting.
    ///
    /// For bulk `.userSearch` data retrieval, see the `ClientController` endpoints.
    ///
    /// - Parameter req: he incoming request `Container`, provided automatically.
    /// - Throws: 403 error if the search term is not permitted.
    /// - Returns: `[UserHeader]` values of all matching users.
    func matchAllNamesHandler(_ req: Request) throws -> EventLoopFuture<[UserHeader]> {
        let requester = try req.auth.require(User.self)
		guard var search = req.parameters.get(searchStringParam.paramString) else {
            throw Abort(.badRequest, reason: "No user search string in request.")
        }
        // postgres "_" and "%" are wildcards, so escape for literals
        search = search.replacingOccurrences(of: "_", with: "\\_")
        search = search.replacingOccurrences(of: "%", with: "\\%")
        // trim and disallow "@" harvesting
        search = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard search != "@", search != "(@" else {
            throw Abort(.forbidden, reason: "'\(search)' is not a permitted search string")
        }
		guard search.count >= 2 else {
            throw Abort(.badRequest, reason: "User search requires at least 2 valid characters in search string..")
        }
        // remove blocks from results
        let blocked = try req.userCache.getBlocks(requester)
		return User.query(on: req.db)
			.filter(\.$userSearch, .custom("ILIKE"), "%\(search)%")
			.filter(\.$id !~ blocked)
			.sort(\.$username, .ascending)
			.all()
			.flatMapThrowing { (profiles) in
				// return as UserSearch
				return try profiles.map { try UserHeader(user: $0) }
		}
    }

    /// `GET /api/v3/users/match/username/STRING`
    ///
    /// Retrieves all usernames containing the specified substring, returning an array
    /// of `@username` strings. The intended use for this endpoint is to help isolate a
    /// particular user in an auto-complete type scenario.
    ///
    /// - Note: An `@` is prepended to each returned matching username as a convenience, but
    ///   should never be included in the search itself. No base username can contain an `@`,
    ///   thus there would never be a match.
    ///
    /// - Parameter req: he incoming request `Container`, provided automatically.
    /// - Returns: `[String]` containng all matching usernames as "@username" strings.
    func matchUsernameHandler(_ req: Request) throws -> EventLoopFuture<[String]> {
        let requester = try req.auth.require(User.self)
		guard var search = req.parameters.get(searchStringParam.paramString) else {
            throw Abort(.badRequest, reason: "No user search string in request.")
        }
        // postgres "_" is wildcard, so escape for literal
        search = search.replacingOccurrences(of: "_", with: "\\_")
        // remove blocks from results
        let blocked = try req.userCache.getBlocks(requester)
		return User.query(on: req.db)
			.filter(\.$username, .custom("ILIKE"), "%\(search)%")
			.filter(\.$id !~ blocked)
			.sort(\.$username, .ascending)
			.all()
			.map { (users) in
				// return @username only
				return users.map { "@\($0.username)" }
			}
    }
    
    /// `POST /api/v3/users/ID/mute`
    ///
    /// Mutes the specified `User` for the current user. The muting user will not see public
    /// posts from the muted user. A mute does not affect what is or is not visible to the
    /// muted user. A mute does not affect private communication channels.
    ///
    /// A mute does not mute any associated sub-accounts of the muted `User`, nor is it applied
    /// to any of the muting user's associated accounts. It is very much just *this* currently
    /// logged-in username muting *that* one username.
    ///
    /// Any user can be muted, including users with privileged `.accessLevel`. Such users are
    /// *not* muted, however, when posting from role accounts. That is, a `.moderator` can post
    /// *as* `@moderator` and it is visible to all users, period.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: 201 Created on success.
    func muteHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
		let requester = try req.auth.require(User.self)
        let requesterID = try requester.requireID()
		guard let parameter = req.parameters.get(userIDParam.paramString), let userID = UUID(parameter) else {
            throw Abort(.badRequest, reason: "No user ID in request.")
        }
		return User.find(userID, on: req.db)
			.unwrap(or: Abort(.notFound, reason: "no user found for identifier '\(parameter)'"))
			.flatMap { (user) in
				// get requester mute barrel
				return Barrel.query(on: req.db)
					.filter(\.$ownerID == requesterID)
					.filter(\.$barrelType == .userMute)
					.first()
					.unwrap(or: Abort(.internalServerError, reason: "userMute barrel not found"))
					.flatMap { (barrel) in
						// add to barrel
						barrel.modelUUIDs.append(userID)
						return barrel.save(on: req.db).flatMap { _ in
							// update cache, return 201
							return req.userCache.updateUser(requesterID).transform(to: .created)
						}
					}
			}
    }

    /// `POST /api/v3/users/ID/note`
    ///
    /// Saves a `UserNote` associated with the specified user and the current user.
	///
    /// - Requires: `NoteCreateData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming `Request`, provided automatically.
    ///   - data: `NoteCreateData` struct containing the text of the note.
    /// - Throws: 400 error if the profile is a banned user's. A 5xx response should be reported as a likely bug, please and
    ///   thank you.
    /// - Returns: `NoteData` containing the newly created note.
    func noteCreateHandler(_ req: Request) throws -> EventLoopFuture<Response> {
        // FIXME: account for banned user
        let requester = try req.auth.require(User.self)
        let data = try req.content.decode(NoteCreateData.self)        
        return User.findFromParameter(userIDParam, on: req)
			.throwingFlatMap { (targetUser) in
            // profile shouldn't be visible, but just in case
            guard targetUser.accessLevel != .banned else {
                throw Abort(.badRequest, reason: "notes are unavailable for profile")
            }
			// check for existing note
			return try requester.$notes.query(on: req.db)
				.filter(\.$noteSubject.$id == targetUser.requireID())
				.first()
				.throwingFlatMap { (existingNote) in
					let note = try existingNote ?? UserNote(author: requester, subject: targetUser, note: data.note)
					note.note = data.note
					// return note's data with 201 response
					return note.save(on: req.db).throwingFlatMap { _ in
						let createdNoteData = try NoteData(note: note, targetUser: targetUser)
						return createdNoteData.encodeResponse(status: .created, for: req)
					}
			}
		}
    }
    
    /// `POST /api/v3/users/ID/note/delete`
    /// `DELETE /api/v3/users/ID/note`
    ///
    /// Deletes an existing `UserNote` associated with the specified user's profile and
    /// the current user.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 400 error if there is no existing note on the profile. A 5xx response should
    ///   be reported as a likely bug, please and thank you.
    /// - Returns: 204 No Content on success.
    func noteDeleteHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        // FIXME: account for blocks, banned user
        let requester = try req.auth.require(User.self)
        return User.findFromParameter(userIDParam, on: req).addModelID()
			.flatMap { (targetUser, targetUserID) in
				// delete note if found
				return requester.$notes.query(on: req.db)
					.filter(\.$noteSubject.$id == targetUserID)
					.first()
					.unwrap(or: Abort(.notFound, reason: "no existing note found"))
					.flatMap { (note) in
						// force true delete
						return note.delete(force: true, on: req.db).transform(to: .noContent)
				}
		}
    }
        
    /// `GET /api/v3/users/ID/note`
    ///
    /// Retrieves an existing `UserNote` associated with the specified user's profile and
    /// the current user.
    ///
    /// - Note: In order to support the editing of a note in contexts other than when
    ///   actively viewing a profile, the contents of `profile.note` cannot be used to determine
    ///   if there is an exiting associated UserNote, since it is possible for a valid note to
    ///   contain no text at any given time. Use this GET endpoint prior to attempting a POST
    ///   to it.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 400 error if there is no existing note on the profile. A 5xx response should
    ///   be reported as a likely bug, please and thank you.
    /// - Returns: `NoteEditData` containing the note's ID and text.
    func noteHandler(_ req: Request) throws -> EventLoopFuture<NoteData> {
        // FIXME: account for blocks, banned user
        let requester = try req.auth.require(User.self)
		guard let parameter = req.parameters.get(userIDParam.paramString), let targetUserID = UUID(parameter) else {
            throw Abort(.badRequest, reason: "No user ID in request.")
        }
		return requester.$notes.query(on: req.db)
			.filter(\.$noteSubject.$id == targetUserID)
			.with(\.$noteSubject)
			.first()
			.unwrap(or: Abort(.badRequest, reason: "no existing note found"))
			.flatMapThrowing { (note) in
				return try NoteData(note: note, targetUser: note.noteSubject)
		}
    }
    
    /// `POST /api/v3/users/ID/report`
    ///
    /// Creates a `Report` regarding the specified `User`.
    ///
    /// - Note: The accompanying report message is optional on the part of the submitting user,
    ///   but the `ReportData` is mandatory in order to allow one. If there is no message,
    ///   send an empty string in the `.message` field.
    ///
    /// - Requires: `ReportData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming `Request`, provided automatically.
    ///   - data: `ReportData` containing an optional accompanying message.
    /// - Returns: 201 Created on success.
    func reportHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let submitter = try req.auth.require(User.self)
        let data = try req.content.decode(ReportData.self)        
		return User.findFromParameter(userIDParam, on: req).throwingFlatMap { reportedUser in
        	return try reportedUser.fileReport(submitter: submitter, submitterMessage: data.message, on: req)
		}
    }
    
    /// `POST /api/v3/users/ID/unblock`
    ///
    /// Removes a block of the specified `User` and all sub-accounts by the current user and
    /// all associated accounts.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 400 error if the specified user was not currently blocked. A 5xx response
    ///   should be reported as a likely bug, please and thank you.
    /// - Returns: 204 No Content on success.
    func unblockHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let requester = try req.auth.require(User.self)
        let requesterID = try requester.requireID()
  		guard let parameter = req.parameters.get(userIDParam.paramString), let userID = UUID(parameter) else {
            throw Abort(.badRequest, reason: "No user ID in request.")
        }
		return User.find(userID, on: req.db)
			.unwrap(or: Abort(.notFound, reason: "no user found for identifier '\(parameter)'"))
			.flatMap { (user) in
				// get requester block barrel
				return Barrel.query(on: req.db)
					.filter(\.$ownerID == requesterID)
					.filter(\.$barrelType == .userBlock)
					.first()
					.unwrap(or: Abort(.internalServerError, reason: "userBlock barrel not found"))
					.flatMap { (barrel) in
						// remove user from barrel
						guard let index = barrel.modelUUIDs.firstIndex(of: userID) else {
							return req.eventLoop.makeFailedFuture(Abort(.badRequest, reason: "user not found in block list"))
						}
						barrel.modelUUIDs.remove(at: index)
						return barrel.save(on: req.db).flatMap { (_) in
							do {
								// update cache and return 204
								return try self.removeBlockFromCache(by: requester, of: user, on: req).transform(to: .noContent)
							}
							catch {
								return req.eventLoop.makeFailedFuture(error)
							}
						}
					}
			}
    }
    
    /// `POST /api/v3/users/ID/unmute`
    ///
    /// Removes a mute of the specified `User` by the current user.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 400 error if the specified user was not currently muted. A 5xx response should
    ///   be reported as a likely bug, please and thank you.
    /// - Returns: 204 No Content on success.
    func unmuteHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let requester = try req.auth.require(User.self)
        let requesterID = try requester.requireID()
  		guard let parameter = req.parameters.get(userIDParam.paramString), let userID = UUID(parameter) else {
            throw Abort(.badRequest, reason: "No user ID in request.")
        }
        return User.find(userID, on: req.db)
			.unwrap(or: Abort(.notFound, reason: "no user found for identifier '\(parameter)'"))
			.flatMap { (user) in
            // get requester mute barrel
            return Barrel.query(on: req.db)
                .filter(\.$ownerID == requesterID)
                .filter(\.$barrelType == .userMute)
                .first()
                .unwrap(or: Abort(.internalServerError, reason: "userMute barrel not found"))
                .flatMap { (barrel) in
                    // remove from barrel
                    guard let index = barrel.modelUUIDs.firstIndex(of: userID) else {
                        return req.eventLoop.makeFailedFuture(Abort(.badRequest, reason: "user not found in mute list"))
                    }
                    barrel.modelUUIDs.remove(at: index)
                    return barrel.save(on: req.db).flatMap { (_) in
                        // update cache, return 204
                    	return req.userCache.updateUser(requesterID).transform(to: .noContent)
                    }
            }
        }
    }
    
    // MARK: - Helper Functions
    
    /// Updates the cache values for all accounts involved in a block removal. The currently
    /// blocked user and any associated accounts are removed from all blocking user's associated
    /// accounts' blocks caches, and vice versa.
    ///
    /// To avoid the potential race condition of multiple blocks being modified simultaneously,
    /// a simple locking scheme is used for the removal processing. A lock expires after 1
    /// second if not explicitly deleted. To avoid resulting potential request fulfillment
    /// blocking, `swiftarr` uses an intermediary to perform the block removals, then updates the
    /// atomic keyedCache used for filtering.
    /// 
    /// - Parameters:
    ///   - requester: The `User` removing the block.
    ///   - user: The `User` currently being blocked.
    ///   - req:The incoming `Request`, which provides the `EventLoop` on which this must run.
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: Void.
    func removeBlockFromCache(by requester: User, of user: User, on req: Request) throws -> EventLoopFuture<Void> {
        // get all involved IDs
        let requesterUUIDs = requester.allAccountIDs(on: req)
        let blockUUIDs = user.allAccountIDs(on: req)
        return requesterUUIDs.and(blockUUIDs).flatMap { (ruuids, buuids) in
			// create lock with 1-second expiry
			let lockValue = UUID().uuidString
			let commandArgs: [RESPValue] = [.simpleString(ByteBuffer(string: "blocksLock")), 
					.simpleString(ByteBuffer(string: "\(lockValue)"))]
			return req.redis.send(command: "SETNX", with: commandArgs)
				.and(req.redis.expire("blocksLock", after: TimeAmount.seconds(1)))
				.flatMap { (_, _) in
                    var futures: [EventLoopFuture<Void>] = []
                    // update requester caches
                    for uuid in ruuids {
                        let redisKey: RedisKey = "rblocks:\(uuid)"
                        let cachedBlocks = req.redis.get(redisKey, as: [String].self)
                        futures.append(cachedBlocks.flatMap { (cached) in
                            var blocks = cached ?? []
                            let removals = buuids.map { "\($0)" }
                            blocks.removeAll(where: { removals.contains($0) })
                            return req.redis.set(redisKey, to: blocks)
                        })
                    }
                    // update blocked user caches
                    for uuid in buuids {
                        let redisKey: RedisKey = "rblocks:\(uuid)"
                        let cachedBlocks = req.redis.get(redisKey, as: [String].self)
                        futures.append(cachedBlocks.flatMap { (cached) in
                            var blocks = cached ?? []
                            let removals = ruuids.map { "\($0)" }
                            blocks.removeAll(where: { removals.contains($0) })
                            return req.redis.set(redisKey, to: blocks)
                        })
                    }
                    // resolve futures
                    return futures.flatten(on: req.eventLoop).flatMap { (_) in
                        // unlock
                        return req.redis.get("blocksLock", as: String.self).throwingFlatMap { (lock) in
                            guard let lock = lock, lock == lockValue else {
                                // hmm... notify of error, just allow lock to expire
                                throw Abort(.internalServerError, reason: "lock conflict")
                            }
                            // delete lock
                            return req.redis.delete("blocksLock").flatMap { _ in 
								return req.userCache.updateUsers(ruuids)
									.and(req.userCache.updateUsers(buuids))
									.transform(to: ())
                            }
                        }
                    }
                }
        }
    }
    
    /// Updates the cache values for all accounts involved in a block. Blocked user and any
    /// associated accounts are added to all blocking user's associated accounts' blocks caches,
    /// and vice versa.
    ///
    /// To avoid the potential race condition of multiple blocks being modified simultaneously,
    /// a simple locking scheme is used for the block generation. A lock expires after 1 second
    /// if not explicitly deleted. To avoid resulting potential request fulfillment blocking,
    /// `swiftarr` uses an intermediary to perform the block additions, then updates the atomic
    /// keyedCache used for filtering.
    ///
    /// - Parameters:
    ///   - requester: The `User` requesting the block.
    ///   - user: The `User` being blocked.
    ///   - req:The incoming `Request`, which provides the `EventLoop` on which this must run.
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: Void.
    func setBlocksCache(by requester: User, of user: User, on req: Request) throws -> EventLoopFuture<Void> {
        // get all involved IDs
        let requesterUUIDs = requester.allAccountIDs(on: req)
        let blockUUIDs = user.allAccountIDs(on: req)
        return requesterUUIDs.and(blockUUIDs).flatMap { (ruuids, buuids) in
			// create lock with 1-second expiry
			let lockValue = UUID().uuidString
			let commandArgs: [RESPValue] = [.simpleString(ByteBuffer(string: "blocksLock")), 
					.simpleString(ByteBuffer(string: "\(lockValue)"))]
			return req.redis.send(command: "SETNX", with: commandArgs)
				.and(req.redis.expire("blocksLock", after: TimeAmount.seconds(1)))
				.flatMap { (_, _) in
				var futures: [EventLoopFuture<Void>] = []
				// update requester caches
				for uuid in ruuids {
					let redisKey: RedisKey = "rblocks:\(uuid)"
					let cachedBlocks = req.redis.get(redisKey, as: [String].self)
					futures.append(cachedBlocks.flatMap { (cached) in
						var blocks = cached ?? []
						blocks += buuids.map { "\($0)" }
						return req.redis.set(redisKey, to: blocks)
					})
				}
				// update blocked user caches
				for uuid in buuids {
					let redisKey: RedisKey = "rblocks:\(uuid)"
					let cachedBlocks = req.redis.get(redisKey, as: [String].self)
					futures.append(cachedBlocks.flatMap { (cached) in
						var blocks = cached ?? []
						blocks += ruuids.map { "\($0)" }
						return req.redis.set(redisKey, to: blocks)
					})
				}
				// resolve futures
				return futures.flatten(on: req.eventLoop).flatMap { (_) in
					// unlock
					return req.redis.get("blocksLock", as: String.self).throwingFlatMap { (lock) in
						guard let lock = lock, lock == lockValue else {
							// hmm... notify of error, just allow lock to expire
							throw Abort(.internalServerError, reason: "lock conflict")
						}
						// delete lock
						return req.redis.delete("blocksLock").flatMap { _ in
							return req.userCache.updateUsers(ruuids)
								.and(req.userCache.updateUsers(buuids))
								.transform(to: ())
						}
					}
				}
			}
		}
	}
}
