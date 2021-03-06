import Vapor

struct ForumAdminData: Content {
    /// The forum's ID.
    var forumID: UUID
    /// The forum's creator.
	var creator: UserHeader
    /// The forum's title.
    var title: String
    /// Time forum was created.
    var createdAt: Date
    /// Whether the forum is in read-only state.
    var moderationStatus: ContentModerationStatus
}

extension ForumAdminData {
	init(_ forum: Forum, on req: Request) throws {
		forumID = try forum.requireID()
		creator = try req.userCache.getHeader(forum.$creator.id)
		title = forum.title
		createdAt = forum.createdAt ?? Date()
		moderationStatus = forum.moderationStatus
		
	}
}

/// Used to return `ForumEdit` data for moderators. The only primary data a ForumEdit stores is the title the forum had before the edit.
///
///	Included in:
///	* `ForumPostModerationData`
///	* `TwarrtModerationData`
///	
/// Returned by:
/// * `GET /api/v3/admin/twarrt/id`
struct ForumEditLogData: Content {
	/// The ID of the forum.
    var forumID: UUID
	/// The ID of the edit.
    var editID: UUID
    /// The timestamp of the edit.
    var createdAt: Date
    /// Who initiated the edit. Usually the forum author, but could be a moderator. Note that the saved edit shows the state BEFORE the edit,
    /// therefore the 'author' here changed the contents to those of the NEXT edit (or to the current state).
    var author: UserHeader
    /// The title of the forum just BEFORE `author` edited it.
    var title: String
}

extension ForumEditLogData {
	init(_ edit: ForumEdit, on req: Request) throws {
		forumID = edit.$forum.id
		editID = try edit.requireID()
		createdAt = edit.createdAt ?? Date()
		author = try req.userCache.getHeader(edit.$editor.id)
		title = edit.title
	}
}

/// Used to return data a moderator needs to moderate a twarrt. 
///	
/// Returned by:
/// * `GET /api/v3/admin/forum/id`
///
/// See `AdminController.forumModerationHandler(_:)`
struct ForumModerationData: Content {
	var forum: ForumAdminData
	var isDeleted: Bool
	var moderationStatus: ContentModerationStatus
	var edits: [ForumEditLogData]
	var reports: [ReportAdminData]
}

/// Used to return data a moderator needs to moderate a twarrt. 
///	
/// Returned by:
/// * `GET /api/v3/admin/forumPost/id`
///
/// See `AdminController.forumPostModerationHandler(_:)`
struct ForumPostModerationData: Content {
	var forumPost: PostDetailData
	var isDeleted: Bool
	var moderationStatus: ContentModerationStatus
	var edits: [PostEditLogData]
	var reports: [ReportAdminData]
}

/// Returns data about an instance of a moderator using their mod powers to edit/delete a user's content, edit a user's profile fields, or change a user's privledges.
struct ModeratorActionLogData: Content {
	/// 
	var id: UUID
	/// 
	var actionType: ModeratorActionType
	///
	var contentType: ReportType
	///
	var contentID: String
	///
	var timestamp: Date
	///
	var moderator: UserHeader
	///
	var targetUser: UserHeader
}

extension ModeratorActionLogData {
	init(action: ModeratorAction, on req: Request) throws {
		id = try action.requireID()
		actionType = action.actionType
		contentType = action.contentType
		contentID = action.contentID
		timestamp = action.createdAt ?? Date()
		moderator = try req.userCache.getHeader(action.$actor.id)
		targetUser = try req.userCache.getHeader(action.$target.id)
	}
}

/// Used to return a `TwarrtEdit` or `ForumPost`'s data for moderators. The two models use the same data structure, as all the fields happen to be the same.
///
///	Included in:
///	* `ForumPostModerationData`
///	* `TwarrtModerationData`
///	
/// Returned by:
/// * `GET /api/v3/admin/twarrt/id`
struct PostEditLogData: Content {
	/// The ID of the post. Depending on context, could be a twarrtID or a forumPostID.
    var postID: Int
	/// The ID of the edit.
    var editID: UUID
    /// The timestamp of the post.
    var createdAt: Date
    /// Who initiated the edit. Usually the post author, but could be a moderator. Note that the saved edit shows the state BEFORE the edit,
    /// therefore the 'author' here changed the contents to those of the NEXT edit (or to the current state).
    var author: UserHeader
    /// The text of the forum post.
    var text: String
    /// The filenames of the twarrt's optional images.
    var images: [String]?
}

extension PostEditLogData {
    init(edit: TwarrtEdit, editor: UserHeader) throws {
    	postID = edit.$twarrt.id
    	editID = try edit.requireID()
    	createdAt = edit.createdAt ?? Date()
    	author = editor
    	text = edit.text
    	images = edit.images    	
    }
    
    init(edit: ForumPostEdit, editor: UserHeader) throws {
    	postID = edit.$post.id
    	editID = try edit.requireID()
    	createdAt = edit.createdAt ?? Date()
    	author = editor
    	text = edit.postText
    	images = edit.images    	
    }
}

/// Used to return data about `Report`s submitted by users. Only Moderators and above have access.
///
/// Required by:
/// * `GET /api/v3/admin/reports`
struct ReportAdminData: Content {
	/// The id of the report.
	var id: UUID
	/// The type of content being reported
	var type: ReportType
	/// The ID of the reported entity. Could resolve to an Int or a UUID, depending on the value of`type`.
	var reportedID: String
	/// The user that authored the content being reported..
	var reportedUser: UserHeader
	/// Text the report author wrote when submitting the report.
	var submitterMessage: String?
	/// The user that submitted the report--NOT the user whose content is being reported.
	var author: UserHeader
	/// The mod who handled (or closed) the report. 
	var handledBy: UserHeader?
	/// TRUE if the report has been closed by moderators.
	var isClosed: Bool
	/// The time the submitter filed the report.
	var creationTime: Date
	/// The last time the report has been modified.
	var updateTime: Date
}

extension ReportAdminData {
	init(req: Request, report: Report) throws {
		id = try report.requireID()
		type = report.reportType
		reportedID = report.reportedID
		reportedUser = try req.userCache.getHeader(report.$reportedUser.id)
		submitterMessage = report.submitterMessage
		isClosed = report.isClosed
		creationTime = report.createdAt ?? Date()
		updateTime = report.updatedAt ?? Date()
		author = try req.userCache.getHeader(report.$submitter.id)
		if let modID = report.$handledBy.id {
			handledBy = try req.userCache.getHeader(modID)
		}
	}
}

/// Used to return data a moderator needs to moderate a twarrt. 
///	
/// Returned by:
/// * `GET /api/v3/admin/twarrt/id`
///
/// See `AdminController.twarrtModerationHandler(_:)`
struct TwarrtModerationData: Content {
	var twarrt: TwarrtData
	var isDeleted: Bool
	var moderationStatus: ContentModerationStatus
	var edits: [PostEditLogData]
	var reports: [ReportAdminData]
}
