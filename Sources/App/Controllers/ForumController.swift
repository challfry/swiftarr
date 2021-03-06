import Vapor
import Crypto
import FluentSQL
import Fluent

/// The collection of `/api/v3/forum/*` route endpoints and handler functions related
/// to forums.

struct ForumController: RouteCollection {
    // MARK: RouteCollection Conformance
        
	// Route path parameters. This trick only works for params that are database IDs and can use findFromParameter().
	let categoryIDParam = PathComponent(":category_id")
	let forumIDParam = PathComponent(":forum_id")
	let postIDParam = PathComponent(":post_id")

	/// Required. Registers routes to the incoming router.
	func boot(routes: RoutesBuilder) throws {
        
		// convenience route group for all /api/v3/forum endpoints
		let forumRoutes = routes.grouped("api", "v3", "forum")
		let eventRoutes = routes.grouped("api", "v3", "events")

		// instantiate authentication middleware
		let basicAuthMiddleware = User.authenticator()
		let guardAuthMiddleware = User.guardMiddleware()
		let tokenAuthMiddleware = Token.authenticator()

		// set protected route groups
		let eventSharedAuthGroup = eventRoutes.grouped([basicAuthMiddleware, tokenAuthMiddleware, guardAuthMiddleware])
		let sharedAuthGroup = forumRoutes.grouped([basicAuthMiddleware, tokenAuthMiddleware, guardAuthMiddleware])
		let tokenAuthGroup = forumRoutes.grouped([tokenAuthMiddleware, guardAuthMiddleware])

		// open access endpoints
		forumRoutes.grouped(tokenAuthMiddleware).get("categories", use: categoriesHandler)

		// endpoints available only when not logged in

		// endpoints available whether logged in or out
		sharedAuthGroup.get(forumIDParam, use: forumHandler)
		sharedAuthGroup.get("categories", categoryIDParam, use: categoryForumsHandler)
		sharedAuthGroup.get("match", ":search_string", use: forumMatchHandler)
		sharedAuthGroup.get("post", postIDParam, use: postHandler)
		sharedAuthGroup.get("post", postIDParam, "forum", use: postForumHandler)
		sharedAuthGroup.get("post", "hashtag", ":hashtag_string", use: postHashtagHandler)
		sharedAuthGroup.get("post", "search", ":search_string", use: postSearchHandler)
		sharedAuthGroup.get(forumIDParam, "search", ":search_string", use: forumSearchHandler)

		eventSharedAuthGroup.get(":event_id", "forum", use: eventForumHandler)

		// endpoints available only when logged in
		tokenAuthGroup.get("bookmarks", use: bookmarksHandler)
		tokenAuthGroup.post("categories", categoryIDParam, "create", use: forumCreateHandler)
		tokenAuthGroup.post(forumIDParam, "favorite", use: favoriteAddHandler)
		tokenAuthGroup.post(forumIDParam, "favorite", "remove", use: favoriteRemoveHandler)
		tokenAuthGroup.get("favorites", use: favoritesHandler)
		tokenAuthGroup.get("likes", use: likesHandler)
		tokenAuthGroup.get("mentions", use: mentionsHandler)
		tokenAuthGroup.get("owner", use: ownerHandler)
		tokenAuthGroup.post("post", postIDParam, "bookmark", use: bookmarkAddHandler)
		tokenAuthGroup.post("post", postIDParam, "bookmark", "remove", use: bookmarkRemoveHandler)
		tokenAuthGroup.post(forumIDParam, "create", use: postCreateHandler)
		tokenAuthGroup.post("post", postIDParam, "delete", use: postDeleteHandler)
		tokenAuthGroup.delete("post", postIDParam, use: postDeleteHandler)
		tokenAuthGroup.post("post", postIDParam, "laugh", use: postLaughHandler)
		tokenAuthGroup.post("post", postIDParam, "like", use: postLikeHandler)
		tokenAuthGroup.post("post", postIDParam, "love", use: postLoveHandler)
		tokenAuthGroup.post("post", postIDParam, "report", use: postReportHandler)
		tokenAuthGroup.post("posts", use: postsHandler)
		tokenAuthGroup.post("post", postIDParam, "unreact", use: postUnreactHandler)
		tokenAuthGroup.delete("post", postIDParam, "laugh", use: postUnreactHandler)
		tokenAuthGroup.delete("post", postIDParam, "like", use: postUnreactHandler)
		tokenAuthGroup.delete("post", postIDParam, "love", use: postUnreactHandler)
		tokenAuthGroup.post("post", postIDParam, "update", use: postUpateHandler)
		tokenAuthGroup.post(forumIDParam, "rename", ":new_name", use: forumRenameHandler)
		tokenAuthGroup.post(forumIDParam, "report", use: forumReportHandler)
		tokenAuthGroup.post(forumIDParam, "delete", use: forumDeleteHandler)
		tokenAuthGroup.delete(forumIDParam, use: forumDeleteHandler)
	}
    
    // MARK: - Open Access Handlers

    /// `GET /api/v3/forum/categories`
    ///
    /// Retrieve a list of  forum `Category`s, sorted by type (admin, user) and title. 
	/// Requiest parameters:
	/// - `?cat=UUID` Only return information about the given category. Will still return an array of `CategoryData`.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[CategoryData]` containing all category IDs and titles.
    func categoriesHandler(_ req: Request) throws -> EventLoopFuture<[CategoryData]> {
        var effectiveAccessLevel: UserAccessLevel = .unverified
        if let user = req.auth.get(User.self) {
        	effectiveAccessLevel = user.accessLevel
        }
    	let futureCategories = Category.query(on: req.db).filter(\.$accessLevelToView <= effectiveAccessLevel)
		if let catID = req.query[UUID.self, at: "cat"]  {
			futureCategories.filter(\.$id == catID)
		}
        return futureCategories.all().flatMapThrowing { (categories) in
			let sortedCats = categories.sorted {
				if $0.accessLevelToView != $1.accessLevelToView {
					return $0.accessLevelToView.rawValue > $1.accessLevelToView.rawValue
				}
				if $0.accessLevelToCreate != $1.accessLevelToCreate {
					return $0.accessLevelToCreate.rawValue > $1.accessLevelToCreate.rawValue
				}
				return $0.title < $1.title
			}
			// return as CategoryData
			return try sortedCats.map {
				try CategoryData($0, restricted: $0.accessLevelToCreate.rawValue > effectiveAccessLevel.rawValue)
			}
        }
    }
    
    // MARK: - basicAuthGroup Handlers (not logged in)
    // All handlers in this route group require a valid HTTP Basic Authentication
    // header in the request.
    
    // MARK: - sharedAuthGroup Handlers (logged in or not)
    // All handlers in this route group require a valid HTTP Basic Authorization
    // *or* HTTP Bearer Authorization header in the request.
    
    /// `GET /api/v3/forum/catgories/ID`
    ///
    /// Retrieve a list of forums in the specifiec `Category`. Will not return forums created by blocked users.
	/// 
	/// * `?sort=STRING` - Sort forums by `create`, `update`, or `title`. Create and update return newest forums first.
	/// * `?start=INT` - The index into the sorted list of forums to start returning results. 0 for first item, which is the default.
	/// * `?limit=INT` - The max # of entries to return. Defaults to 50
	/// 
	/// These options set the anchor point for returning threads. By default the anchor is 'newest create date'. When sorting on 
	/// update time, these params may be used to ensure a series of calls see (mostly) contiguous resullts. As users keep posting
	/// to threads, the sorting for most recently updated threads is constantly changing. A paged UI, for example, may show N threads
	/// per page and use beforedate/afterdate as the user moves between pages to ensure continuity.
	/// When sorting on update time, afterdate and beforedate operate on the threads' update time. Create and Alpha sort use create time.
	/// These options are mutally exclusive; if both are present, beforeDate will be used.
	/// * `?afterdate=DATE` - 
	/// * `?beforedate=DATE` - 
	/// 
	/// With no parameters, defaults to `?sort=create&start=0&limit=50`.
	/// 
	/// If you want to ensure you have all the threads in a category, you can sort by create time and ask for threads newer than 
	/// the last time you asked. If you want to update last post times and post counts, you can sort by update time and get the
	/// latest updates. 
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 404 error if the category ID is not valid.
    /// - Returns: `CategoryData` containing category forums.
    func categoryForumsHandler(_ req: Request) throws -> EventLoopFuture<CategoryData> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        let start = (req.query[Int.self, at: "start"] ?? 0)
        let limit = (req.query[Int.self, at: "limit"] ?? 50).clamped(to: 0...200)
        // get user's taggedForum barrel, and category
        return user.getBookmarkBarrel(of: .taggedForum, on: req)
        	.and(Category.findFromParameter(categoryIDParam, on: req).addModelID()).flatMap { (barrel, categoryTuple) in
            let (category, categoryID) = categoryTuple
			// remove blocks from results, unless it's an admin category
			let blocked = category.accessLevelToCreate.hasAccess(.moderator) ? [] : req.userCache.getBlocks(userID)
			// sort user categories
			let query = Forum.query(on: req.db)
				.filter(\.$category.$id == categoryID)
				.filter(\.$creator.$id !~ blocked)
				.range(start..<(start + limit))
			var dateFilterUsesUpdate = false
			switch req.query[String.self, at: "sort"] {
				case "update": _ = query.sort(\.$updatedAt, .descending); dateFilterUsesUpdate = true
				case "title": _ = query.sort(\.$title, .ascending)
				default: _ = query.sort(\.$createdAt, .descending)
			}
			if let beforeDate = req.query[Date.self, at: "beforedate"] {
				query.filter((dateFilterUsesUpdate ? \.$updatedAt : \.$createdAt) < beforeDate)
			}
			else if let afterDate = req.query[Date.self, at: "afterdate"] {
				query.filter((dateFilterUsesUpdate ? \.$updatedAt : \.$createdAt) > afterDate)
			}
			return query.all().flatMap { (forums) in
				return buildForumListData(forums, on: req, userID: userID, favoritesBarrel: barrel).flatMapThrowing { forumList in
					return try CategoryData(category, restricted: category.accessLevelToCreate.rawValue > user.accessLevel.rawValue,
							forumThreads: forumList)
				}
			}
        }
    }
    
    /// `GET /api/v3/forum/ID`
    ///
    /// Retrieve a `Forum` with all its `ForumPost`s. Content from blocked or muted users,
    /// or containing user's muteWords, is not returned. Posts are always sorted by creation time.
    ///
	/// Query parameters:
	/// * `?start=INT` - The index into the array of posts to start returning results. 0 for first post. Not compatible with `startPost`.
	/// * `?startPost=INT` - PostID of a post in the thread.  Acts as if `start` had been used with the index of this post within the thread.
	/// * `?limit=INT` - The max # of entries to return. Defaults to 50. Clamped to a max value set in Settings.
	/// 
	/// The first post in the result `posts` array (assuming it isn't blocked/muted) will be, in priority order:
	/// 	- The `start`-th post in the thread (first post has index 0).
	/// 	- The post with id of `startPost`
	/// 	- The page of thread posts (with `limit` as pagesize) that contains the last post read by the user.
	/// 	- The first post in the thread.
	/// 
	/// Start and Limit do not take blocks and mutes into account, matching the behavior of the totalPosts values. Instead, when asking for e.g. the first 50 posts in a thread,
	/// you may only receive 46 posts, as 4 posts in that batch were blocked/muted. To continue reading the thread, ask to start with post 50 (not post 47)--you'll receive however
	/// many posts are viewable by the user in the range 50...99 . Doing it this way makes Forum read counts invariant to blocks--if a user reads a forum, then blocks a user, then
	/// comes back to the forum, they should come back to the same place they were in previously.
	///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 404 error if the forum is not available.
    /// - Returns: `ForumData` containing the forum's metadata and posts.
    func forumHandler(_ req: Request) throws -> EventLoopFuture<ForumData> {
        return Forum.findFromParameter(forumIDParam, on: req).throwingFlatMap { forum in
			return try buildForumData(forum, on: req)
		}
	}
	
    
    /// `GET /api/v3/forum/match/STRING`
    ///
    /// Retrieve all `Forum`s in all categories whose title contains the specified string.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[ForumListData]` containing all matching forums.
    func forumMatchHandler(_ req: Request) throws -> EventLoopFuture<[ForumListData]> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        guard var search = req.parameters.get("search_string") else {
            throw Abort(.badRequest, reason: "Missing search parameter.")
        }
        // postgres "_" and "%" are wildcards, so escape for literals
        search = search.replacingOccurrences(of: "_", with: "\\_")
        search = search.replacingOccurrences(of: "%", with: "\\%")
        search = search.trimmingCharacters(in: .whitespacesAndNewlines)
		// get user's blocks and taggedForum barrel
		return user.getBookmarkBarrel(of: .taggedForum, on: req)
     		.throwingFlatMap { (barrel) in
                // get forums, remove blocks
        		let blocked = try req.userCache.getBlocks(user)
                return Forum.query(on: req.db)
                    .filter(\.$creator.$id !~ blocked)
                    .filter(\.$title, .custom("ILIKE"), "%\(search)%")
                    .all()
                    .flatMap { (forums) in
                    	return buildForumListData(forums, on: req, userID: userID, favoritesBarrel: barrel)
                	}
            }
    }
    
    /// `GET /api/v3/forum/ID/search/STRING`
    ///
    /// Retrieve all `ForumPost`s in the specified `Forum` that contain the specified string.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[PostData]` containing all matching posts in the forum.
    func forumSearchHandler(_ req: Request) throws -> EventLoopFuture<[PostData]> {
        let user = try req.auth.require(User.self)
        let cacheUser = try req.userCache.getUser(user)
        guard var search = req.parameters.get("search_string") else {
            throw Abort(.badRequest, reason: "Missing search parameter.")
        }
		// postgres "_" and "%" are wildcards, so escape for literals
		search = search.replacingOccurrences(of: "_", with: "\\_")
		search = search.replacingOccurrences(of: "%", with: "\\%")
		search = search.trimmingCharacters(in: .whitespacesAndNewlines)
		// get forum and cached blocks
        return Forum.findFromParameter(forumIDParam, on: req).flatMap { forum in
			// get posts
			return forum.$posts.query(on: req.db)
				.filter(\.$author.$id !~ cacheUser.getBlocks())
				.filter(\.$author.$id !~ cacheUser.getMutes())
				.filter(\.$text, .custom("ILIKE"), "%\(search)%")
				.all()
				.flatMap { (posts) in
					return buildPostData(posts, user: user, on: req, mutewords: cacheUser.mutewords)
				}
		}
    }
    
    /// `GET /api/v3/forum/post/ID/forum`
    ///
    /// Retrieve the `ForumData` of the specified `ForumPost`'s parent `Forum`.
    ///
	/// Query parameters:
	/// * `?start=INT` - The index into the array of posts to start returning results. 0 for first post.
	/// * `?limit=INT` - The max # of entries to return. Defaults to 50. Clamped to a max value set in Settings.
	/// 
	/// The first post in the result `posts` array (assuming it isn't blocked/muted) will be, in priority order:
	/// 	- The `start`-th post in the thread (first post has index 0).
	/// 	- The post with ID given by the `ID` path parameter
	///
	/// Start and Limit do not take blocks and mutes into account, matching the behavior of the totalPosts values. Instead, when asking for e.g. the first 50 posts in a thread,
	/// you may only receive 46 posts, as 4 posts in that batch were blocked/muted. To continue reading the thread, ask to start with post 50 (not post 47)--you'll receive however
	/// many posts are viewable by the user in the range 50...99 . Doing it this way makes Forum read counts invariant to blocks--if a user reads a forum, then blocks a user, then
	/// comes back to the forum, they should come back to the same place they were in previously.
	///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: `ForumData` containing the post's parent forum.
    func postForumHandler(_ req: Request) throws -> EventLoopFuture<ForumData> {
		return ForumPost.findFromParameter(postIDParam, on: req).flatMap { post in
			return post.$forum.get(on: req.db).throwingFlatMap { forum in
				return try buildForumData(forum, on: req)
			}
		}
	}
    
    /// `GET /api/v3/events/ID/forum`
    ///
    /// Retrieve the `Forum` associated with an `Event`, with its `ForumPost`s. Content from
    /// blocked or muted users, or containing user's muteWords, is not returned.
	///
	/// Query parameters:
	/// * `?start=INT` - The index into the array of posts to start returning results. 0 for first post. Default is the last post the user read, rounded down to a multiple of `limit`.
	/// * `?limit=INT` - The max # of entries to return. Defaults to 50. Clamped to a max value set in Settings.
	/// 
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: `ForumData` containing the forum's metadata and all posts.
    func eventForumHandler(_ req: Request) throws -> EventLoopFuture<ForumData> {
    	return Event.findFromParameter("event_id", on: req).flatMap { event in
			guard let forumID = event.$forum.id else {
				return req.eventLoop.makeFailedFuture(Abort(.internalServerError, reason: "event has no forum"))
			}
			return Forum.find(forumID, on: req.db).unwrap(or: Abort(.internalServerError, reason: "forum not found"))
					.throwingFlatMap { forum in
				return try buildForumData(forum, on: req)
			}
		}
	}


    /// `GET /api/v3/forum/post/ID`
    ///
    /// Retrieve the specified `ForumPost` with full user `LikeType` data.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 404 error if the post is not available.
    /// - Returns: `PostDetailData` containing the specified post.
    func postHandler(_ req: Request) throws -> EventLoopFuture<PostDetailData> {
        let user = try req.auth.require(User.self)
        let cacheUser = try req.userCache.getUser(user)
        return ForumPost.findFromParameter(postIDParam, on: req).addModelID().flatMap { (post, postID) in
			if cacheUser.getBlocks().contains(post.$author.id) || cacheUser.getMutes().contains(post.$author.id) ||
					post.containsMutewords(using: cacheUser.mutewords ?? []) {
				return req.eventLoop.makeFailedFuture(Abort(.notFound, reason: "post is not available"))
			}
			// get likes data and bookmark state
			return PostLikes.query(on: req.db)
				.filter(\.$post.$id == postID)
				.all()
				.and(user.hasBookmarked(post, on: req))
				.flatMapThrowing { (postLikes, bookmarked) in
					let laughUsers = postLikes.filter { $0.likeType == .laugh }.map { $0.$user.id }
					let likeUsers = postLikes.filter { $0.likeType == .like }.map { $0.$user.id }
					let loveUsers = postLikes.filter { $0.likeType == .love }.map { $0.$user.id }
					// init return struct
					var postDetailData = try PostDetailData(post: post, author: req.userCache.getHeader(post.$author.id))
					postDetailData.isBookmarked = bookmarked
					postDetailData.laughs = req.userCache.getHeaders(laughUsers).map { SeaMonkey(header: $0) }
					postDetailData.likes = req.userCache.getHeaders(likeUsers).map { SeaMonkey(header: $0) }
					postDetailData.loves = req.userCache.getHeaders(loveUsers).map { SeaMonkey(header: $0) }
					return postDetailData
            }
		}
    }
    
    /// `GET /api/v3/forum/post/hashtag/#STRING`
    ///
    /// Retrieve all `ForumPost`s that contain the exact specified hashtag.
    ///
    /// - Note: By "exact" we mean the string cannot be a substring of another hashtag (there
    ///   must be a trailing space), but the match is not case-sensitive. For example, `#joco`
    ///   will not match `#joco2020` or `#joco#2020`, but will match `#JoCo`. Use the more
    ///   generic `GET /api/v3/forum/post/search/STRING` endpoint with the same `#joco`
    ///   parameter if you want that type of substring matching behavior.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 400 error if the specified string is not a hashtag.
    /// - Returns: `[PostData]` containing all matching posts.
    func postHashtagHandler(_ req: Request) throws -> EventLoopFuture<[PostData]> {
        let user = try req.auth.require(User.self)
		let cachedUser = try req.userCache.getUser(user)
        guard var hashtag = req.parameters.get("hashtag_string") else {
            throw Abort(.badRequest, reason: "Missing hashtag parameter.")
        }
        // ensure it's a hashtag
        guard hashtag.hasPrefix("#") else {
            throw Abort(.badRequest, reason: "hashtag parameter must start with '#'")
        }
        // postgres "_" and "%" are wildcards, so escape for literals
        hashtag = hashtag.replacingOccurrences(of: "_", with: "\\_")
        hashtag = hashtag.replacingOccurrences(of: "%", with: "\\%")
        hashtag = hashtag.trimmingCharacters(in: .whitespacesAndNewlines)
		// get posts
		return ForumPost.query(on: req.db)
			.filter(\.$author.$id !~ cachedUser.getBlocks())
			.filter(\.$author.$id !~ cachedUser.getMutes())
			.filter(\.$text, .custom("ILIKE"), "%\(hashtag) %")
			.all()
			.flatMap { (posts) in
				return buildPostData(posts, user: user, on: req, mutewords: cachedUser.mutewords)
			}
    }
    
    /// `GET /api/v3/forum/post/search/STRING`
    ///
    /// Retrieve all `ForumPost`s that contain the specified string.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[PostData]` containing all matching posts.
    func postSearchHandler(_ req: Request) throws -> EventLoopFuture<[PostData]> {
        let user = try req.auth.require(User.self)
		let cachedUser = try req.userCache.getUser(user)
        guard var search = req.parameters.get("search_string") else {
            throw Abort(.badRequest, reason: "Missing search parameter.")
        }
        // postgres "_" and "%" are wildcards, so escape for literals
        search = search.replacingOccurrences(of: "_", with: "\\_")
        search = search.replacingOccurrences(of: "%", with: "\\%")
        search = search.trimmingCharacters(in: .whitespacesAndNewlines)
		// get posts
		return ForumPost.query(on: req.db)
			.filter(\.$author.$id !~ cachedUser.getBlocks())
			.filter(\.$author.$id !~ cachedUser.getMutes())
			.filter(\.$text, .custom("ILIKE"), "%\(search)%")
			.all()
			.flatMap { (posts) in
				return buildPostData(posts, user: user, on: req, mutewords: cachedUser.mutewords)
			}
    }
    
    // MARK: - tokenAuthGroup Handlers (logged in)
    // All handlers in this route group require a valid HTTP Bearer Authentication
    // header in the request.
    
    /// `POST /api/v3/forum/post/ID/bookmark`
    ///
    /// Add a bookmark of the specified `ForumPost`.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 400 error if the post is already bookmarked.
    /// - Returns: 201 Created on success.
    func bookmarkAddHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        // get post and user's bookmarkedPost barrel
        return ForumPost.findFromParameter(postIDParam, on: req)
        	.and(user.getBookmarkBarrel(of: .bookmarkedPost, on: req))
        	.flatMapThrowing { (post, bookmarkBarrel) -> Barrel in
                // create barrel if needed
                let barrel = bookmarkBarrel ?? Barrel(ownerID: userID, barrelType: .bookmarkedPost)
                // ensure bookmark doesn't exist
                var bookmarks = barrel.userInfo["bookmarks"] ?? []
                let postIDStr = try post.bookmarkIDString()
                guard !bookmarks.contains(postIDStr) else {
                    throw Abort(.badRequest, reason: "post already bookmarked")
                }
                // add post and return 201
                bookmarks.append(postIDStr)
                barrel.userInfo["bookmarks"] = bookmarks
                return barrel
			}
			.flatMap { barrel in
                return barrel.save(on: req.db).transform(to: .created)
            }
    }
    
    /// `POST /api/v3/forum/post/ID/bookmark/remove`
    ///
    /// Remove a bookmark of the specified `ForumPost`.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 400 error if the user has not bookmarked any posts.
    func bookmarkRemoveHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
        // get post and user's bookmarkedPost barrel
        return ForumPost.findFromParameter(postIDParam, on: req)
        	.and(user.getBookmarkBarrel(of: .bookmarkedPost, on: req))
        	.flatMapThrowing { (post, bookmarkBarrel) -> Barrel in
                guard let barrel = bookmarkBarrel else {
                    throw Abort(.badRequest, reason: "user has not bookmarked any posts")
                }
                var bookmarks = barrel.userInfo["bookmarks"] ?? []
                // remove post and return 204
                let postIDStr = try post.bookmarkIDString()
                if let index = bookmarks.firstIndex(of: postIDStr) {
                    bookmarks.remove(at: index)
                }
                barrel.userInfo["bookmarks"] = bookmarks
                return barrel
			}
			.flatMap { barrel in
                return barrel.save(on: req.db).transform(to: .noContent)
            }
    }
    
    /// `GET /api/v3/forum/bookmarks`
    ///
    /// Retrieve all `ForumPost`s the user has bookmarked, sorted by creation timestamp.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[PostData]` containing all bookmarked posts.
    func bookmarksHandler(_ req: Request) throws -> EventLoopFuture<[PostData]> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        // get bookmarkedPost barrel
        return user.getBookmarkBarrel(of: .bookmarkedPost, on: req).flatMap { (barrel) in
            let bookmarkStrings = barrel?.userInfo["bookmarks"] ?? []
            // convert to IDs
            let bookmarks = bookmarkStrings.compactMap { Int($0) }
            // filter blocks only
            let blocked = req.userCache.getBlocks(userID)
			// get twarrts
			return ForumPost.query(on: req.db)
				.filter(\.$id ~~ bookmarks)
				.filter(\.$author.$id !~ blocked)
				.sort(\.$createdAt, .ascending)
				.all()
				.flatMap { (posts) in
					return buildPostData(posts, user: user, on: req, assumeBookmarked: true)
            }
        }
    }
    
    /// `POST /api/v3/forum/ID/favorite`
    ///
    /// Add the specified `Forum` to the user's tagged forums list.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: 201 Created on success.
    func favoriteAddHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        // get forum and barrel
        return Forum.findFromParameter(forumIDParam, on: req).addModelID()
        	.and(user.getBookmarkBarrel(of: .taggedForum, on: req)
        			.unwrap(orReplace: Barrel(ownerID: userID, barrelType: .taggedForum)))
        	.flatMap { (arg0, barrel) in
        		let (_, forumID) = arg0
				// add forum and return 201
				barrel.modelUUIDs.append(forumID)
				return barrel.save(on: req.db).transform(to: .created)
            }
    }
    
    /// `POST /api/v3/forum/ID/favorite/remove`
    ///
    /// Remove the specified `Forum` from the user's tagged forums list.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 400 error if the forum was not favorited.
    /// - Returns: 204 No Content on success.
    func favoriteRemoveHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
        // get forum
        return Forum.findFromParameter(forumIDParam, on: req).addModelID()
			.and(user.getBookmarkBarrel(of: .taggedForum, on: req))
        	.flatMap { (arg0, forumBarrel) in
        		let (_, forumID) = arg0
				guard let barrel = forumBarrel else {
					return req.eventLoop.makeFailedFuture(Abort(.badRequest, reason: "user has not tagged any forums"))
				}
				// remove event
				guard let index = barrel.modelUUIDs.firstIndex(of: forumID) else {
					return req.eventLoop.makeFailedFuture(Abort(.badRequest, reason: "forum was not tagged"))
				}
				barrel.modelUUIDs.remove(at: index)
				return barrel.save(on: req.db).transform(to: .noContent)
            }
    }
    
    /// `GET /api/v3/forum/favorites`
    ///
    /// Retrieve the `Forum`s in the user's taggedForum barrel, sorted by title.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[ForumListData]` containing the user's favorited forums.
    func favoritesHandler(_ req: Request) throws -> EventLoopFuture<[ForumListData]> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        // get user's taggedForum barrel
        return user.getBookmarkBarrel(of: .taggedForum, on: req).flatMap { (barrel) in
            guard let barrel = barrel else {
                 return req.eventLoop.future([])
            }
            // respect blocks
            let blocked = req.userCache.getBlocks(userID)
			// get forums
			return Forum.query(on: req.db)
				.filter(\.$id ~~ barrel.modelUUIDs)
				.filter(\.$creator.$id !~ blocked)
				.sort(\.$title, .ascending)
				.all()
				.flatMap { (forums) in
					return buildForumListData(forums, on: req, userID: userID, forceIsFavorite: true)
            }
        }
    }
    
    /// `POST /api/v3/forum/categories/ID/create`
    ///
    /// Creates a new `Forum` in the specified `Category`, and the first `ForumPost` within
    /// the newly created forum. Creating a forum in an `.isRestricted` category requires
    /// administrative access.
    ///
    /// - Requires: `ForumCreateData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming `Request`, provided automatically.
    ///   - data: `ForumCreateData` containing the forum's title and initial post contents.
    /// - Throws: 403 error if the user is not authorized to create a forum.
    /// - Returns: `ForumData` containing the new forum's contents.
    func forumCreateHandler(_ req: Request) throws -> EventLoopFuture<ForumData> {
        let user = try req.auth.require(User.self)
		// see `ForumCreateData.validations()`
		try user.guardCanCreateContent()
		let data = try ValidatingJSONDecoder().decode(ForumCreateData.self, fromBodyOf: req)
        // check authorization to create
        return Category.findFromParameter(categoryIDParam, on: req).throwingFlatMap { (category) in
            guard user.accessLevel.hasAccess(category.accessLevelToCreate) else {
				return req.eventLoop.makeFailedFuture(Abort(.forbidden, reason: "users cannot create forums in category"))
            }
			// process images
			return self.processImages(data.firstPost.images, usage: .forumPost, on: req).throwingFlatMap { (imageFilenames) in
				// create forum
				let forum = try Forum(title: data.title, category: category, creator: user, isLocked: false)
				return forum.save(on: req.db).throwingFlatMap { (_) in
                    // create first post
                    let forumPost = try ForumPost(forum: forum, author: forum.creator, text: data.firstPost.text, images: imageFilenames)
                    // return as ForumData
                    return forumPost.save(on: req.db).flatMapThrowing { (_) in
                    	// Update Category
                    	_ = category.$forums.query(on: req.db).count().map { count -> EventLoopFuture<Void> in
                    		category.forumCount = Int32(count)
                    		return category.save(on: req.db)                    		
                    	}
                    
                    	let creatorHeader = try req.userCache.getHeader(user.requireID())
                    	let postData = try PostData(post: forumPost, author: creatorHeader, 
                    			bookmarked: false, userLike: nil, likeCount: 0)
						let forumData = try ForumData(forum: forum, creator: creatorHeader,
								isFavorite: false, posts: [postData])
						return forumData
                    }
                }
            }
        }
    }
        
    /// `POST /api/v3/forum/ID/rename/:new_name`
    ///
    /// Rename the specified `Forum` to the specified title string.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 403 error if the user does not have credentials to modify the forum. 404 error
    ///   if the forum ID is not valid.
    /// - Returns: 201 Created on success.
    func forumRenameHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
		guard let nameParameter = req.parameters.get("new_name"), nameParameter.count > 0 else {
			throw Abort(.badRequest, reason: "No new name parameter for forum name change.")
		}
        return Forum.findFromParameter(forumIDParam, on: req).throwingFlatMap { (forum) in
            // must be forum owner or .moderator
			try user.guardCanModifyContent(forum, customErrorString: "User cannot modify forum title.")
			if forum.title != nameParameter {
				_ = try ForumEdit(forum: forum, editor: user).save(on: req.db)
            	forum.title = nameParameter
  				forum.logIfModeratorAction(.edit, user: user, on: req)
				return forum.save(on: req.db).transform(to: .created)
			}
			return req.eventLoop.future(.created)
        }
    }
    
    /// `POST /api/v3/forum/ID/report`
    ///
    /// Creates a `Report` regarding the specified `Forum`.
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
    func forumReportHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
        let data = try req.content.decode(ReportData.self)
        return Forum.findFromParameter(forumIDParam, on: req).throwingFlatMap { forum in
        	return try forum.fileReport(submitter: user, submitterMessage: data.message, on: req)
		}
    }
    
    /// `POST /api/v3/forum/ID/delete`
	/// `DELETE /api/v3/forum/ID`
    ///
    /// Delete the specified `Forum`. This soft-deletes the forum itself and all the forum's posts.
	/// 
	/// To delete, the user must have an access level allowing them to delete the forum. Currently this means moderators and above.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 403 error if the user is not permitted to delete.
    /// - Returns: 204 No Content on success.
    func forumDeleteHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
        guard user.accessLevel.canEditOthersContent() else {
			throw Abort(.forbidden, reason: "User does not have access to delete forums.")
        }
        return Forum.findFromParameter(forumIDParam, on: req).flatMap { forum in
			return forum.$category.get(on: req.db).throwingFlatMap { category in
				try user.guardCanModifyContent(forum)
				forum.logIfModeratorAction(.delete, user: user, on: req)
				return try ForumPost.query(on: req.db).filter(\.$forum.$id == forum.requireID()).delete().throwingFlatMap {
					return forum.delete(on: req.db).flatMap { _ in
						// Update Category
						return category.$forums.query(on: req.db).count().flatMap { count in
							category.forumCount = Int32(count)
							return category.save(on: req.db).transform(to: .noContent)            		
						}
					}
				}
			}
        }
    }
    
    /// `GET /api/v3/forum/likes`
    ///
    /// Retrieve all `ForumPost`s the user has liked.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[PostData]` containing all liked posts.
    func likesHandler(_ req: Request) throws -> EventLoopFuture<[PostData]> {
        let user = try req.auth.require(User.self)
        // respect blocks
        let blocked = try req.userCache.getBlocks(user)
		// get liked posts
		return user.$postLikes.query(on: req.db)
			.filter(\.$author.$id !~ blocked)
			.all()
			.flatMap { (posts) in
				return buildPostData(posts, user: user, on: req)
        }
    }
    
    /// `GET /api/v3/forum/mentions`
    ///
    /// Retrieve all `ForumPost`s whose content mentions the user.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[PostData]` containing all posts containing mentions.
    func mentionsHandler(_ req: Request) throws -> EventLoopFuture<[PostData]> {
        let user = try req.auth.require(User.self)
        // respect blocks
        let blocked = try req.userCache.getBlocks(user)
		// get mention posts
		return ForumPost.query(on: req.db)
			.filter(\.$author.$id !~ blocked)
			.filter(\.$text, .custom("ILIKE"), "%@\(user.username) %")
			.sort(\.$createdAt, .ascending)
			.all()
			.flatMap { (posts) in
				return buildPostData(posts, user: user, on: req)
        }
    }
    
    /// `GET /api/v3/forum/owner`
    /// `GET /api/v3/user/forums`
    ///
    /// Retrieve a list of all `Forum`s created by the user, sorted by title.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[ForumListData]` containing all forums created by the user.
    func ownerHandler(_ req: Request) throws-> EventLoopFuture<[ForumListData]> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        // get user's taggedForum barrel
        return user.getBookmarkBarrel(of: .taggedForum, on: req).flatMap { (barrel) in
            return user.$forums.query(on: req.db)
                .sort(\.$title, .ascending)
                .all()
                .flatMap { (forums) in
					return buildForumListData(forums, on: req, userID: userID, favoritesBarrel: barrel)
            	}
        }
    }
    
    /// `POST /api/v3/forum/ID/create`
    ///
    /// Create a new `ForumPost` in the specified `Forum`.
    ///
    /// - Requires: `PostContentData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming `Request`, provided automatically.
    /// - Throws: 403 error if the forum is locked or user is blocked.
    /// - Returns: `PostData` containing the post's contents and metadata.
    func postCreateHandler(_ req: Request) throws -> EventLoopFuture<Response> {
        let user = try req.auth.require(User.self)
        let cacheUser = try req.userCache.getUser(user)
        // see `PostContentData.validations()`
 		let newPostData = try ValidatingJSONDecoder().decode(PostContentData.self, fromBodyOf: req)
        // get forum
        return Forum.findFromParameter(forumIDParam, on: req).throwingFlatMap { (forum) in
			try guardUserCanPostInForum(user, in: forum)
            // ensure user has access to forum; user cannot retrieve block-owned forum, but prevent end-run
			guard !cacheUser.getBlocks().contains(forum.$creator.id) else {
				throw Abort(.forbidden, reason: "user cannot post in forum")
			}
			// process images
			return self.processImages(newPostData.images, usage: .forumPost, on: req).throwingFlatMap { (filenames) in
				// create post
				let forumPost = try ForumPost(forum: forum, author: user, text: newPostData.text, images: filenames)
				return forumPost.save(on: req.db).flatMapThrowing { (_) in
					// return as PostData, with 201 status
					let response = Response(status: .created)
					try response.content.encode(PostData(post: forumPost, author: cacheUser.makeHeader()))
					return response
				}
			}
        }
    }
    
    /// `POST /api/v3/forum/post/ID/delete`
	/// `DELETE /api/v3/forum/post/ID`
    ///
    /// Delete the specified `ForumPost`.
	/// 
	/// To delete, the user must have an access level allowing them to delete the post, and the forum itself must not be locked or in quarantine.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 403 error if the user is not permitted to delete.
    /// - Returns: 204 No Content on success.
    func postDeleteHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
        return ForumPost.findFromParameter(postIDParam, on: req).flatMap { post in
        	return post.$forum.load(on: req.db).throwingFlatMap {
				try guardUserCanPostInForum(user, in: post.forum, editingPost: post)
  				post.logIfModeratorAction(.delete, user: user, on: req)
        	    return post.delete(on: req.db).transform(to: .noContent)
			}
        }
    }
    
    /// `POST /api/v3/forum/post/ID/report`
    ///
    /// Create a `Report` regarding the specified `ForumPost`.
    ///
    /// - Note: The accompanying report message is optional on the part of the submitting user,
    ///   but the `ReportData` is mandatory in order to allow one. If there is no message,
    ///   send an empty string in the `.message` field.
    ///
    /// - Requires: `ReportData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming `Request`, provided automatically.
    ///   - data: `ReportData` containing an optional accompanying message.
    /// - Throws: 409 error if user has already reported the post.
    /// - Returns: 201 Created on success.
    func postReportHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
        let data = try req.content.decode(ReportData.self)
        return ForumPost.findFromParameter(postIDParam, on: req).throwingFlatMap { post in
        	return try post.fileReport(submitter: user, submitterMessage: data.message, on: req)
		}
    }
    
    /// `POST /api/v3/forum/post/ID/laugh`
    ///
    /// Add a "laugh" reaction to the specified `ForumPost`. If there is an existing `LikeType`
    /// reaction by the user, it is replaced.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 403 error if user is the post's creator.
    /// - Returns: `PostData` containing the updated like info.
    func postLaughHandler(_ req: Request) throws -> EventLoopFuture<PostData> {
    	return try postReactHandler(req, likeType: .laugh)
    }
    
        /// `POST /api/v3/forum/post/ID/like`
    ///
    /// Add a "like" reaction to the specified `ForumPost`. If there is an existing `LikeType`
    /// reaction by the user, it is replaced.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 403 error if user is the post's creator.
    /// - Returns: `PostData` containing the updated like info.
    func postLikeHandler(_ req: Request) throws -> EventLoopFuture<PostData> {
    	return try postReactHandler(req, likeType: .like)
	}
    
    /// `POST /api/v3/forum/post/ID/love`
    ///
    /// Add a "love" reaction to the specified `ForumPost`. If there is an existing `LikeType`
    /// reaction by the user, it is replaced.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 403 error if user is the post's creator.
    /// - Returns: `PostData` containing the updated like info.
    func postLoveHandler(_ req: Request) throws -> EventLoopFuture<PostData> {
    	return try postReactHandler(req, likeType: .love)
	}
	
	func postReactHandler(_ req: Request, likeType: LikeType) throws -> EventLoopFuture<PostData> {
        let user = try req.auth.require(User.self)
		let userID = try user.requireID()
        // get post
        return ForumPost.findFromParameter(postIDParam, on: req).addModelID().flatMap { (post, postID) in
            guard post.$author.id != userID else {
                return req.eventLoop.makeFailedFuture(Abort(.forbidden, reason: "user cannot like own post"))
            }
			return post.$likes.attachOrEdit(from: post, to: user, on: req.db) { postLike in
				postLike.likeType = likeType
			}.flatMap { 
				return buildPostData([post], user: user, on: req).map { postDataArray in
					return postDataArray[0]
				}
			}
		}
	}

    /// `GET /api/v3/forum/posts`
    ///
    /// Retrieve all `ForumPost`s authored by the user.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[PostData]` containing all posts authored by the user.
    func postsHandler(_ req: Request) throws -> EventLoopFuture<[PostData]> {
        let user = try req.auth.require(User.self)
        // get posts
        return user.$posts.query(on: req.db)
            .sort(\.$createdAt, .ascending)
            .all()
            .flatMap { (posts) in
				return buildPostData(posts, user: user, on: req)
        	}
    }
    
    /// `POST /api/v3/forum/post/ID/unreact`
    ///
    /// Remove a `LikeType` reaction from the specified `ForumPost`.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 400 error if there was no existing reaction. 403 error if user is the post's
    ///   creator.
    /// - Returns: `PostData` containing the updated like info.
    func postUnreactHandler(_ req: Request) throws -> EventLoopFuture<PostData> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        // get post
        return ForumPost.findFromParameter(postIDParam, on: req).addModelID().flatMap { (post, postID) in
            guard post.$author.id != userID else {
                return req.eventLoop.makeFailedFuture(Abort(.forbidden, reason: "user cannot like own post"))
            }
			// check for existing like
			return PostLikes.query(on: req.db)
				.filter(\.$user.$id == userID)
				.filter(\.$post.$id == postID)
				.first()
				.throwingFlatMap { (like) in
					guard like != nil else {
						throw Abort(.badRequest, reason: "user does not have a reaction on the post")
					}
					// remove pivot
					return post.$likes.detach(user, on: req.db).flatMap { (_) in
						return buildPostData([post], user: user, on: req).map { postDataArray in
							return postDataArray[0]
						}
					}
				}
        }
    }
    
    /// `POST /api/v3/forum/post/ID/update`
    ///
    /// Update the specified `ForumPost`.
    ///
    /// - Requires: `PostContentData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming `Request`, provided automatically.
    /// - Throws: 403 error if user is not post owner or has read-only access.
    /// - Returns: `PostData` containing the post's contents and metadata.
    func postUpateHandler(_ req: Request) throws -> EventLoopFuture<Response> {
        let user = try req.auth.require(User.self)
		// see `PostContentData.validations()`
		let newPostData = try ValidatingJSONDecoder().decode(PostContentData.self, fromBodyOf: req)
        return ForumPost.findFromParameter(postIDParam, on: req).addModelID().flatMap { (post, postID) in
        	return post.$forum.load(on: req.db).throwingFlatMap {
				// ensure user has write access, the post can be modified by them, and the forum isn't locked.
				try guardUserCanPostInForum(user, in: post.forum, editingPost: post)
				// process images
				return self.processImages(newPostData.images, usage: .forumPost, on: req).throwingFlatMap { (filenames) in
					// update if there are changes
					let normalizedText = newPostData.text.replacingOccurrences(of: "\r\n", with: "\r")
					if post.text != normalizedText || post.images != filenames {
						// stash current contents first
						let forumEdit = try ForumPostEdit(post: post)
						post.text = normalizedText
						post.images = filenames
  						post.logIfModeratorAction(.edit, user: user, on: req)
						return post.save(on: req.db).and(forumEdit.save(on: req.db)).transform(to: (post, true))
					}
					return req.eventLoop.future((post, false))
				}
				.flatMap { (post, wasCreated: Bool) in
					// return updated post as PostData, with 200 or 201 status
					return buildPostData([post], user: user, on: req).flatMapThrowing { postDataArray in
						let response = Response(status: wasCreated ? .created : .ok)
						try response.content.encode(postDataArray[0])
						return response
					}
				}
			}
		}
    }
}

// Utilities for route methods
extension ForumController {

	/// Ensures the given user has appropriate access to create or edit posts in the given forum. If editing a post, you must pass the post in the `editingPost` parameter.
	func guardUserCanPostInForum(_ user: User, in forum: Forum, editingPost: ForumPost? = nil) throws {
		if let post = editingPost {
			try user.guardCanModifyContent(post) 
		}
		else {
			try user.guardCanCreateContent()
		}
		guard user.accessLevel.canEditOthersContent() || (forum.moderationStatus == .normal || forum.moderationStatus == .modReviewed) else {
			throw Abort(.forbidden, reason: "Forum is locked.")
		}
	}
	
	/// Builds an array of `ForumListData` from the given `Forums`. `ForumListData` does not return post content, but does return post counts.
	func buildForumListData(_ forums: [Forum], on req: Request, userID: UUID,
			favoritesBarrel: Barrel? = nil, forceIsFavorite: Bool? = nil) -> EventLoopFuture<[ForumListData]> {
		// get forum metadata
		var forumCounts: [EventLoopFuture<Int>] = []
		var forumLastPosts: [EventLoopFuture<ForumPost?>] = []
		var readerPivots: [EventLoopFuture<ForumReaders?>] = []
		for forum in forums {
			forumCounts.append(forum.$posts.query(on: req.db).count())
			forumLastPosts.append(forum.$posts.query(on: req.db).sort(\.$createdAt, .descending).first())
			readerPivots.append(forum.$readers.$pivots.query(on: req.db).filter(\.$user.$id == userID).first())
		}
		// resolve futures
		return forumCounts.flatten(on: req.eventLoop).and(forumLastPosts.flatten(on: req.eventLoop))
				.flatMap { (counts, lastPosts) in
			return readerPivots.flatten(on: req.eventLoop).flatMapThrowing { readCounts in
				// return as ForumListData
				var returnListData: [ForumListData] = []
				for (index, forum) in forums.enumerated() {
					let creatorHeader = try req.userCache.getHeader(forum.$creator.id)
					var lastPosterHeader: UserHeader? 
					var lastPostTime: Date? 
					if let lastPost = lastPosts[index] {
						lastPosterHeader = try req.userCache.getHeader(lastPost.$author.id)
						lastPostTime = lastPost.createdAt
					}
					returnListData.append(
						try ForumListData(
							forum: forum, 
							creator: creatorHeader, 
							postCount: counts[index], 
							readCount: readCounts[index]?.readCount ?? 0, 
							lastPostAt: lastPostTime,
							lastPoster: lastPosterHeader,
							isFavorite: forceIsFavorite ?? favoritesBarrel?.contains(forum) ?? false)
					)
				}
				return returnListData
			}
		}
	}
	
	/// Builds a `ForumData` with the contents of the given `Forum`. Uses the requests' "limit" and "start" query parameters
	/// to return only a subset of the forums' posts (for forums where postCount > limit).
	func buildForumData(_ forum: Forum, on req: Request, startPostID: Int? = nil) throws -> EventLoopFuture<ForumData> {
		let user = try req.auth.require(User.self)
		let userID = try user.requireID()
		let cacheUser = try req.userCache.getUser(user)
		return forum.$posts.query(on: req.db).count().flatMap { postCount in
			return forum.$readers.$pivots.query(on: req.db).filter(\.$user.$id == userID).first()
					.and(user.getBookmarkBarrel(of: .taggedForum, on: req)).flatMap { (readerPivot, favoriteForumBarrel) in
				let clampedReadCount = min(readerPivot?.readCount ?? 0, postCount)
				let limit = (req.query[Int.self, at: "limit"] ?? 50).clamped(to: 1...Settings.shared.maximumForumPosts)
				var future: EventLoopFuture<(Int?, Int)>
				if let startParam = req.query[Int.self, at: "start"] {
					let startCount = max(startParam, 0)
					// Get the 'start' post without filtering blocks and mutes
					future = forum.$posts.query(on: req.db)
							.sort(\.$createdAt, .ascending)
							.range(startCount...startCount)
							.first()
							.flatMapThrowing { startPost in
						return try (startPost?.requireID(), startCount)
					}
				}
				else if let startPostIDParam = req.query[Int.self, at: "startPost"] {
					future = forum.$posts.query(on: req.db).filter(\.$id < startPostIDParam).count().map { (startCount: Int) in
						return (startPostIDParam, startCount)
					}
				}
				else {
					let defaultStart = max((clampedReadCount / limit) * limit, 0)
					// Get the 'start' post without filtering blocks and mutes
					future = forum.$posts.query(on: req.db)
							.sort(\.$createdAt, .ascending)
							.range(defaultStart...defaultStart)
							.first()
							.flatMapThrowing { startPost in
						return try (startPost?.requireID(), defaultStart)
					}
				}
				return future.throwingFlatMap { (resolvedStartPostID: Int?, start: Int) in
					// filter posts
					var query = forum.$posts.query(on: req.db)
							.filter(\.$author.$id !~ cacheUser.getBlocks())
							.filter(\.$author.$id !~ cacheUser.getMutes())
							.sort(\.$createdAt, .ascending)
					if let resolvedStartPostID = resolvedStartPostID {
						query = query.range(0..<limit).filter(\.$id >= resolvedStartPostID)
					}
					else {
						query = query.range(start...start + limit)
					}
					return query.all().flatMap { (posts) -> EventLoopFuture<ForumData> in
						if let pivot = readerPivot {
							let newReadCount = min(start + limit, postCount)
							if newReadCount > pivot.readCount || pivot.readCount > postCount {
								pivot.readCount = newReadCount
								_ = pivot.save(on: req.db)
							}
						}
						else {
							_ = forum.$readers.attach(user, on: req.db) { newReader in 
								newReader.readCount = min(start + limit, postCount)
							}
						}
						return buildPostData(posts, user: user, on: req, mutewords: cacheUser.mutewords).flatMapThrowing { flattenedPosts in
							let creatorHeader = try req.userCache.getHeader(forum.$creator.id)
							var result = try ForumData(forum: forum, creator: creatorHeader, 
									isFavorite: favoriteForumBarrel?.contains(forum) ?? false, posts: flattenedPosts)
							result.start = start
							result.limit = limit
							result.totalPosts = postCount
							return result
						}
					}
				}
			}
		}
	}
		
	// Builds an array of PostData structures from the given posts, adding the user's bookmarks and likes
	// for the post, as well as the total count of likes. The optional parameters are for callers that
	// only need some of the functionality, or for whom some of the values are known in advance e.g.
	// the method that returns a user's bookmarked posts can assume all the posts it finds are in fact bookmarked.
	func buildPostData(_ posts: [ForumPost], user: User, on req: Request,
			mutewords: [String]? = nil, assumeBookmarked: Bool? = nil, assumeLikeType: LikeType? = nil) -> EventLoopFuture<[PostData]> {

		// remove muteword posts
		var filteredPosts = posts
		if let mutes = mutewords {
			 filteredPosts = posts.compactMap { $0.filterMutewords(using: mutes) }
		}
		// convert to PostData
		let postsData = filteredPosts.map { (filteredPost) -> EventLoopFuture<PostData> in
			do {
      			let author = try req.userCache.getHeader(filteredPost.$author.id)
				let bookmarked = assumeBookmarked == nil ? user.hasBookmarked(filteredPost, on: req) :
						req.eventLoop.future(assumeBookmarked!)
				let processUserLike = try author.userID != user.requireID() && assumeLikeType == nil
				let userLike = processUserLike ? try PostLikes.query(on: req.db)
					.filter(\.$post.$id == filteredPost.requireID())
					.filter(\.$user.$id == user.requireID())
					.first().map { $0?.likeType } : req.eventLoop.future(assumeLikeType)
				let likeCount = try PostLikes.query(on: req.db)
					.filter(\.$post.$id  == filteredPost.requireID())
					.count()
				return bookmarked.and(userLike).and(likeCount).flatMapThrowing { (arg0, count) in
					let (bookmarked, userLike) = arg0
					return try PostData(post: filteredPost, author: author, bookmarked: bookmarked, 
							userLike: userLike, likeCount: count)
				}
			}
			catch {
				return req.eventLoop.makeFailedFuture(error)
			}
		}
		return postsData.flatten(on: req.eventLoop)
	}
}
