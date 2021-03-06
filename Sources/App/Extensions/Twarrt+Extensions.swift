import Vapor
import Fluent

// MARK: - Functions

// twarrts can be filtered by author and content
extension Twarrt: ContentFilterable {
    /// Checks if a `Twarrt` contains any of the provided array of muting strings, returning true if it does
    ///
    /// - Parameters:
    ///   - mutewords: The list of strings on which to filter the post.
    /// - Returns: The provided post, or `nil` if the post contains a muting string.
    func containsMutewords(using mutewords: [String]) -> Bool {
        for word in mutewords {
            if self.text.range(of: word, options: .caseInsensitive) != nil {
                return true
            }
        }
        return false
    }
    
    /// Checks if a `Twarrt` contains any of the provided array of muting strings, returning
    /// either the original twarrt or `nil` if there is a match.
    ///
    /// - Parameters:
    ///   - post: The `Event` to filter.
    ///   - mutewords: The list of strings on which to filter the post.
    ///   - req: The incoming `Request` on whose event loop this needs to run.
    /// - Returns: The provided post, or `nil` if the post contains a muting string.
    func filterMutewords(using mutewords: [String]?) -> Twarrt? {
		if let mutewords = mutewords {
			for word in mutewords {
				if self.text.range(of: word, options: .caseInsensitive) != nil {
					return nil
				}
			}
		}
        return self
    }
    
}

// twarrts can be bookmarked
extension Twarrt: UserBookmarkable {
    /// The barrel type for `Twarrt` bookmarking.
	var bookmarkBarrelType: BarrelType {
        return .bookmarkedTwarrt
    }
    
    func bookmarkIDString() throws -> String {
    	return try String(self.requireID())
    }
}

// twarrts can be reported
extension Twarrt: Reportable {
    /// The type for `Twarrt` reports.
	var reportType: ReportType { .twarrt }
    
	var authorUUID: UUID { $author.id }
	
	var autoQuarantineThreshold: Int { Settings.shared.postAutoQuarantineThreshold }
}
