import CoreData

struct PersistenceController {

    static let shared = PersistenceController()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {

        container = NSPersistentContainer(name: "RestodocksModel")
        // ⬆️ ВАЖНО: имя должно ТОЧНО совпадать с .xcdatamodeld

        if inMemory {
            container.persistentStoreDescriptions.first?.url =
                URL(fileURLWithPath: "/dev/null")
        }

        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                fatalError("❌ CoreData load error: \(error), \(error.userInfo)")
            }
        }

        container.viewContext.mergePolicy =
            NSMergeByPropertyObjectTrumpMergePolicy

        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}