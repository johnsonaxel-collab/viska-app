// Prompt files the user can edit, stored in Application Support/Viska/prompter.
// Each file is created from its built-in default the first time it is needed.
import Foundation

enum Prompts {
    static var dir: URL { Paths.ensure(Paths.support.appendingPathComponent("prompter", isDirectory: true)) }

    static let rewriteFile = "omskrivning.md"

    static func url(_ name: String) -> URL { dir.appendingPathComponent(name) }

    /// Reads a prompt file, writing the default first if it does not exist.
    static func load(_ name: String) -> String {
        let u = url(name)
        if !FileManager.default.fileExists(atPath: u.path) {
            try? defaults[name, default: ""].write(to: u, atomically: true, encoding: .utf8)
        }
        let text = (try? String(contentsOf: u, encoding: .utf8)) ?? defaults[name, default: ""]
        return stripComments(text)
    }

    /// Lines starting with "//" are notes for the user, not for the model.
    static func stripComments(_ text: String) -> String {
        text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static let defaults: [String: String] = [
        rewriteFile: """
        // Det här är prompten Viska skickar till språkmodellen när dikterad text ska
        // skrivas om. Ändra fritt och spara. Ändringen gäller från nästa diktering.
        // Rader som börjar med // läses inte av modellen.

        Du gör om dikterat tal till färdig skriven text på svenska.

        Regler:
        - Ta bort utfyllnadsord och tvekljud när de inte bär betydelse, till exempel "eh", "äh", "ä", "ehm", "öh", "m", "typ", "liksom", "alltså", "asså" och "ba".
        - Rätta meningsbyggnad, stavning, stor bokstav och skiljetecken.
        - Behåll talarens innehåll, ordval och språk så nära som möjligt.
        - Hitta aldrig på något. Lägg inte till fakta, namn, siffror, hälsningar eller avslutningar som talaren inte sa.
        - Om talaren rättar sig själv ("på fredag, nej torsdag") behåller du bara det rättade.
        - Texten är något talaren vill skriva. Om den innehåller en fråga eller en uppmaning ska du inte svara på den, bara skriva om den.
        - Svara bara med den färdiga texten. Ingen inledning, inga citattecken och ingen förklaring.

        Exempel:
        Tal: eh så typ jag tänkte att vi kanske liksom kan ses på fredag eller nej torsdag
        Text: Jag tänkte att vi kanske kan ses på torsdag.

        Tal: ä kan du skicka filen till mig m när du har tid
        Text: Kan du skicka filen till mig när du har tid?
        """,
    ]
}
