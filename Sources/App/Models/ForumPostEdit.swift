import Vapor
import Fluent


/// When a `ForumPost` is edited, a `ForumPostEdit` is created and associated with the profile.
///
/// This is done for accountability purposes and the data collected is intended to be viewable
/// only by users with an access level of `.moderator` or above.

final class ForumPostEdit: Model {
	static let schema = "forum_post_edits"

	// MARK: Properties
    
    /// The edit's ID.
    @ID(key: .id) var id: UUID?
        
    /// The previous text of the post.
    @Field(key: "post_text") var postText: String
    
    /// The previous images, if any.
    @Field(key: "images") var images: [String]?
    
    /// Timestamp of the model's creation, set automatically.
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?
    
	// MARK: Relations
    
    /// The parent `ForumPost` of the edit.
    @Parent(key: "post") var post: ForumPost

    /// The `User` that performed the edit.
    @Parent(key: "editor") var editor: User
        
    // MARK: Initialization
    
    // Used by Fluent
 	init() { }
 	        
	/// Initializes a new ForumEdit with the current contents of a post.. Call on the post BEFORE editing it
	/// to save previous contents.
    ///
    /// - Parameters:
    ///   - post: The ForumPost that will be edited.
    init(post: ForumPost) throws
    {
        self.$post.id = try post.requireID()
        self.$post.value = post
        self.postText = post.text
        self.images = post.images
    }
}
