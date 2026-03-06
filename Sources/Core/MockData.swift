import Foundation

/// Sample data for SwiftUI previews and testing
public enum MockData {

    public static let todoItems: [Item] = [
        Item(
            type: "todo",
            title: "Review PR for authentication",
            properties: [
                "priority": .text("high"),
                "dueDate": .date(Date().addingTimeInterval(86400 * 2))
            ],
            tags: ["work/backend", "urgent"],
            completed: false,
            sourceFile: "Work/Tasks.md"
        ),
        Item(
            type: "todo",
            title: "Update API documentation",
            properties: [
                "priority": .text("medium"),
                "dueDate": .date(Date().addingTimeInterval(86400 * 5))
            ],
            tags: ["work/docs"],
            completed: false,
            sourceFile: "Work/Tasks.md"
        ),
        Item(
            type: "todo",
            title: "Fix login bug on Safari",
            properties: [
                "priority": .text("high"),
                "dueDate": .date(Date().addingTimeInterval(-86400))
            ],
            tags: ["work/backend", "bugs"],
            completed: false,
            sourceFile: "Work/Bugs.md"
        ),
        Item(
            type: "todo",
            title: "Deploy staging environment",
            properties: [
                "priority": .text("medium"),
                "dueDate": .date(Date().addingTimeInterval(86400 * 3))
            ],
            tags: ["work/devops"],
            completed: false,
            sourceFile: "Work/Tasks.md"
        ),
        Item(
            type: "todo",
            title: "Write unit tests for filter engine",
            properties: [
                "priority": .text("low"),
                "dueDate": .date(Date().addingTimeInterval(86400 * 10))
            ],
            tags: ["work/backend", "testing"],
            completed: false,
            sourceFile: "Work/Tasks.md"
        ),
        Item(
            type: "todo",
            title: "Buy groceries",
            tags: ["personal/errands"],
            completed: false,
            sourceFile: "Personal/Tasks.md"
        ),
        Item(
            type: "todo",
            title: "Schedule dentist appointment",
            tags: ["personal/health"],
            completed: true,
            sourceFile: "Personal/Tasks.md"
        ),
        Item(
            type: "todo",
            title: "Plan weekend trip",
            properties: [
                "dueDate": .date(Date().addingTimeInterval(86400 * 4))
            ],
            tags: ["personal/travel"],
            completed: false,
            sourceFile: "Personal/Tasks.md"
        ),
        Item(
            type: "todo",
            title: "Update resume",
            properties: [
                "priority": .text("low")
            ],
            tags: ["personal/career"],
            completed: true,
            sourceFile: "Personal/Tasks.md"
        ),
        Item(
            type: "todo",
            title: "Code review: new search feature",
            properties: [
                "priority": .text("high"),
                "dueDate": .date(Date().addingTimeInterval(86400))
            ],
            tags: ["work/frontend", "urgent"],
            completed: false,
            sourceFile: "Work/Tasks.md"
        ),
    ]

    public static let bookItems: [Item] = [
        Item(
            type: "book",
            title: "Project Hail Mary",
            properties: [
                "author": .text("Andy Weir"),
                "rating": .number(5.0),
                "date_read": .date(Date().addingTimeInterval(-86400 * 30))
            ],
            tags: ["books/read", "sci-fi"],
            completed: true,
            sourceFile: "Books/Project Hail Mary.md"
        ),
        Item(
            type: "book",
            title: "The Pragmatic Programmer",
            properties: [
                "author": .text("David Thomas & Andrew Hunt"),
                "rating": .number(4.5)
            ],
            tags: ["books/to-read", "tech"],
            completed: false,
            sourceFile: "Books/Pragmatic Programmer.md"
        ),
        Item(
            type: "book",
            title: "Dune",
            properties: [
                "author": .text("Frank Herbert"),
                "rating": .number(4.0),
                "date_read": .date(Date().addingTimeInterval(-86400 * 90))
            ],
            tags: ["books/read", "sci-fi", "classic"],
            completed: true,
            sourceFile: "Books/Dune.md"
        ),
        Item(
            type: "book",
            title: "Designing Data-Intensive Applications",
            properties: [
                "author": .text("Martin Kleppmann")
            ],
            tags: ["books/to-read", "tech"],
            completed: false,
            sourceFile: "Books/DDIA.md"
        ),
        Item(
            type: "book",
            title: "The Three-Body Problem",
            properties: [
                "author": .text("Cixin Liu"),
                "rating": .number(4.0),
                "date_read": .date(Date().addingTimeInterval(-86400 * 60))
            ],
            tags: ["books/read", "sci-fi"],
            completed: true,
            sourceFile: "Books/Three Body Problem.md"
        ),
    ]

    public static let movieItems: [Item] = [
        Item(
            type: "movie",
            title: "Oppenheimer",
            properties: [
                "director": .text("Christopher Nolan"),
                "rating": .number(4.5),
                "year": .number(2023)
            ],
            tags: ["movies/watched", "drama", "biography"],
            completed: true,
            sourceFile: "Movies/Oppenheimer.md"
        ),
        Item(
            type: "movie",
            title: "Dune: Part Two",
            properties: [
                "director": .text("Denis Villeneuve"),
                "year": .number(2024)
            ],
            tags: ["movies/to-watch", "sci-fi"],
            completed: false,
            sourceFile: "Movies/Dune Part Two.md"
        ),
        Item(
            type: "movie",
            title: "The Shawshank Redemption",
            properties: [
                "director": .text("Frank Darabont"),
                "rating": .number(5.0),
                "year": .number(1994)
            ],
            tags: ["movies/watched", "drama", "classic"],
            completed: true,
            sourceFile: "Movies/Shawshank.md"
        ),
    ]

    public static let allItems: [Item] = todoItems + bookItems + movieItems

    public static let savedViews: [SavedView] = [
        SavedView(
            name: "Urgent Work Tasks",
            filters: ViewFilters(
                tags: ["work/*", "urgent"],
                itemTypes: ["todo"],
                completed: false
            ),
            displayStyle: .list
        ),
        SavedView(
            name: "Reading List",
            filters: ViewFilters(
                tags: ["books/to-read"],
                itemTypes: ["book"],
                completed: false
            ),
            displayStyle: .card
        ),
        SavedView(
            name: "All Incomplete",
            filters: ViewFilters(completed: false),
            displayStyle: .list
        ),
        SavedView(
            name: "Completed Items",
            filters: ViewFilters(completed: true),
            displayStyle: .list
        ),
        SavedView(
            name: "Movies to Watch",
            filters: ViewFilters(
                tags: ["movies/to-watch"],
                itemTypes: ["movie"],
                completed: false
            ),
            displayStyle: .card
        ),
    ]

    public static let listTypes: [ListType] = [
        ListType(
            name: "Todo",
            fields: [
                FieldDefinition(name: "title", type: .text, required: true),
                FieldDefinition(name: "dueDate", type: .date),
                FieldDefinition(name: "priority", type: .text),
            ]
        ),
        ListType(
            name: "Book",
            fields: [
                FieldDefinition(name: "title", type: .text, required: true),
                FieldDefinition(name: "author", type: .text),
                FieldDefinition(name: "rating", type: .number, min: 1, max: 5),
                FieldDefinition(name: "date_read", type: .date),
            ],
            llmExtractionPrompt: "Extract book metadata including title, author, ISBN, and rating from the following text."
        ),
        ListType(
            name: "Movie",
            fields: [
                FieldDefinition(name: "title", type: .text, required: true),
                FieldDefinition(name: "director", type: .text),
                FieldDefinition(name: "rating", type: .number, min: 1, max: 5),
                FieldDefinition(name: "year", type: .number),
            ]
        ),
        ListType(
            name: "Restaurant",
            fields: [
                FieldDefinition(name: "name", type: .text, required: true),
                FieldDefinition(name: "cuisine", type: .text),
                FieldDefinition(name: "rating", type: .number, min: 1, max: 5),
                FieldDefinition(name: "price_range", type: .text),
            ]
        ),
    ]
}
