import Intents

final class IntentHandler: INExtension, SelectStatusWidgetIntentHandling {
    override func handler(for intent: INIntent) -> Any { self }

    func defaultProvider1(for intent: SelectStatusWidgetIntent) -> StatusWidgetProvider? {
        self.emptyChoice()
    }

    func defaultProvider2(for intent: SelectStatusWidgetIntent) -> StatusWidgetProvider? {
        self.emptyChoice()
    }

    func defaultProvider3(for intent: SelectStatusWidgetIntent) -> StatusWidgetProvider? {
        self.emptyChoice()
    }

    func defaultProvider4(for intent: SelectStatusWidgetIntent) -> StatusWidgetProvider? {
        self.emptyChoice()
    }

    func defaultPaceProvider(for intent: SelectStatusWidgetIntent) -> StatusWidgetProvider? {
        self.emptyChoice()
    }

    func provideProvider1OptionsCollection(
        for intent: SelectStatusWidgetIntent,
        with completion: @escaping (INObjectCollection<StatusWidgetProvider>?, Error?) -> Void)
    {
        self.provideOptions(with: completion)
    }

    func provideProvider2OptionsCollection(
        for intent: SelectStatusWidgetIntent,
        with completion: @escaping (INObjectCollection<StatusWidgetProvider>?, Error?) -> Void)
    {
        self.provideOptions(with: completion)
    }

    func provideProvider3OptionsCollection(
        for intent: SelectStatusWidgetIntent,
        with completion: @escaping (INObjectCollection<StatusWidgetProvider>?, Error?) -> Void)
    {
        self.provideOptions(with: completion)
    }

    func provideProvider4OptionsCollection(
        for intent: SelectStatusWidgetIntent,
        with completion: @escaping (INObjectCollection<StatusWidgetProvider>?, Error?) -> Void)
    {
        self.provideOptions(with: completion)
    }

    func providePaceProviderOptionsCollection(
        for intent: SelectStatusWidgetIntent,
        with completion: @escaping (INObjectCollection<StatusWidgetProvider>?, Error?) -> Void)
    {
        self.provideOptions(with: completion)
    }

    private func provideOptions(
        with completion: @escaping (INObjectCollection<StatusWidgetProvider>?, Error?) -> Void)
    {
        do {
            let records = try WidgetProviderCatalogue.read()
            let choices = records.map { StatusWidgetProvider(identifier: $0.id, display: $0.name) }
            completion(INObjectCollection(items: [self.emptyChoice()] + choices), nil)
        } catch {
            completion(nil, error)
        }
    }

    private func emptyChoice() -> StatusWidgetProvider {
        StatusWidgetProvider(
            identifier: StatusWidgetProviderChoice.emptyIdentifier,
            display: String(
                localized: "Not selected",
                comment: "An unused provider slot; leaving every slot unused selects providers automatically."))
    }
}
