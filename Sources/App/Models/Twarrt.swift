import Vapor
import Fluent


/// An individual post within the Twit-arr stream. A Twarrt must contain either text
/// content or image content, or both.

final class Twarrt: Model {
	static let schema = "twarrts"
	
	// MARK: Properties
    
    /// The twarrt's ID.
    @ID(custom: "id") var id: Int?
    
    /// The text content of the twarrt.
    @Field(key: "text") var text: String
    
    /// The filenames of any images for the post.
    @Field(key: "images") var images: [String]?
    
    /// Moderators can set several statuses on twarrts that modify editability and visibility.
    @Enum(key: "mod_status") var moderationStatus: ContentModerationStatus
        
    /// Timestamp of the model's creation, set automatically.
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?
    
    /// Timestamp of the model's last update, set automatically.
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?
    
    /// Timestamp of the model's soft-deletion, set automatically.
    @Timestamp(key: "deleted_at", on: .delete) var deletedAt: Date?
    
	// MARK: Relations
	
    /// The twarrt's author.
    @Parent(key: "author") var author: User

    /// The twarrt being replied to, if any.
    @OptionalParent(key: "reply_to") var replyTo: Twarrt?
    
    /// The child `TwarrtEdit` accountability records of the twarrt.
	@Children(for: \.$twarrt) var edits: [TwarrtEdit]
	
    /// The sibling `User`s who have "liked" the twarrt.
	@Siblings(through: TwarrtLikes.self, from: \.$twarrt, to: \.$user) var likes: [User]
	
	// MARK: Initialization
    
    // Used by Fluent
 	init() { }
 	
    /// Initialized a new Twarrt.
    ///
    /// - Parameters:
    ///   - author: The author of the twarrt.
    ///   - text: The text content of the twarrt.
    ///   - image: The filename of any image content of the twarrt.
    ///   - replyTo: The twarrt being replied to, if any.
    init(
        author: User,
        text: String,
        images: [String]? = nil,
        replyTo: Twarrt? = nil
    ) throws {
        self.$author.id = try author.requireID()
        self.$author.value = author
        // We don't do much text manipulation on input, but let's normalize line endings.
        self.text = text.replacingOccurrences(of: "\r\n", with: "\r")
        self.images = images
        self.$replyTo.id = replyTo?.id
        self.$replyTo.value = replyTo
        self.moderationStatus = .normal
    }
}
