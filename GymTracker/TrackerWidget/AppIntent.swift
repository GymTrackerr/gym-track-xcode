//
//  AppIntent.swift
//  TrackerWidget
//
//  Created by Daniel Kravec on 2025-12-07.
//

import WidgetKit
import AppIntents

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource {
        LocalizedStringResource(
            "widget.configuration.title",
            defaultValue: "Configuration",
            table: "Widgets",
            comment: "Title for the widget configuration intent."
        )
    }
    static var description: IntentDescription {
        IntentDescription(LocalizedStringResource(
            "widget.configuration.description",
            defaultValue: "This is an example widget.",
            table: "Widgets",
            comment: "Description for the widget configuration intent."
        ))
    }

    // An example configurable parameter.
    @Parameter(title: "Favorite Emoji", default: "😃")
    var favoriteEmoji: String
}
