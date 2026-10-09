import Intents

final class IntentHandler: INExtension, SelectStatusWidgetIntentHandling, SelectQuotaPaceWidgetIntentHandling {
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

    func defaultProvider(for intent: SelectQuotaPaceWidgetIntent) -> StatusWidgetProvider? {
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

    func provideProviderOptionsCollection(
        for intent: SelectQuotaPaceWidgetIntent,
        with completion: @escaping (INObjectCollection<StatusWidgetProvider>?, Error?) -> Void)
    {
        self.provideOptions(with: completion)
    }

    /// Research/071: the window list follows the provider currently set on
    /// the widget being edited. SiriKit asks again every time the picker
    /// opens, so changing the provider changes the offered windows.
    func defaultQuotaWindow(for intent: SelectQuotaPaceWidgetIntent) -> QuotaPaceWindowOption? {
        self.defaultWindowChoice()
    }

    func provideQuotaWindowOptionsCollection(
        for intent: SelectQuotaPaceWidgetIntent,
        with completion: @escaping (INObjectCollection<QuotaPaceWindowOption>?, Error?) -> Void)
    {
        do {
            let providerID = intent.provider?.identifier
            let record = try WidgetProviderCatalogue.read().first { $0.id == providerID }
            let options = QuotaPaceWindowChoice.options(
                for: record,
                preferredLocalizations: Bundle.main.preferredLocalizations,
                defaultTitle: QuotaPaceWindowChoice.defaultTitle,
                durationText: QuotaPaceWindowChoice.durationText)
            let items = options.map { option in
                QuotaPaceWindowOption(
                    identifier: option.identifier,
                    display: option.title,
                    subtitle: option.subtitle,
                    image: nil)
            }
            completion(INObjectCollection(items: items), nil)
        } catch {
            // An unreadable catalogue still offers the default window.
            completion(INObjectCollection(items: [self.defaultWindowChoice()]), nil)
        }
    }

    private func defaultWindowChoice() -> QuotaPaceWindowOption {
        QuotaPaceWindowOption(
            identifier: QuotaPaceWindowChoice.defaultIdentifier,
            display: QuotaPaceWindowChoice.defaultTitle)
    }

    /// An unreadable catalogue still offers "Not selected" (Research/072).
    private func provideOptions(
        with completion: @escaping (INObjectCollection<StatusWidgetProvider>?, Error?) -> Void)
    {
        let choices = StatusWidgetProviderChoice.choices { try WidgetProviderCatalogue.read() }
            .map { StatusWidgetProvider(identifier: $0.id, display: $0.name) }
        completion(INObjectCollection(items: choices), nil)
    }

    private func emptyChoice() -> StatusWidgetProvider {
        StatusWidgetProvider(
            identifier: StatusWidgetProviderChoice.emptyIdentifier,
            display: StatusWidgetProviderChoice.emptyTitle)
    }
}
