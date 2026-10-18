// Unit tests for Viska's core logic. Run: ./tests/run.sh
import Foundation

var failures = 0
func check(_ cond: Bool, _ name: String, file: String = #file, line: Int = #line) {
    if cond { print("  ok   \(name)") } else { print("  FEL  \(name) (rad \(line))"); failures += 1 }
}

print("TranscriptCleaner")
check(TranscriptCleaner.clean(" [BLANK_AUDIO]\n") == "", "tar bort [BLANK_AUDIO]")
check(TranscriptCleaner.clean("\n Hej  Anna,\n vi ses.\n") == "Hej Anna, vi ses.", "slår ihop rader och mellanrum")
check(TranscriptCleaner.clean("Hej (skratt) då") == "Hej (skratt) då", "rör inte parenteser")

print("ModelCatalog")
check(ModelCatalog.byId("noggrann") == ModelCatalog.accurate, "hittar noggrann")
check(ModelCatalog.byId(nil) == ModelCatalog.fast, "snabb är standard")
check(ModelCatalog.byId("okänd") == ModelCatalog.fast, "okänt id ger snabb")
check(ModelCatalog.fast.downloadURL.absoluteString
      == "https://huggingface.co/KBLab/kb-whisper-small/resolve/main/ggml-model-q5_0.bin", "rätt nedladdningsadress")

print("Multipart")
let body = Multipart.body(boundary: "B", fields: [("language", "sv")], fileField: "file",
                          fileName: "a.wav", fileData: Data([1, 2, 3]))
let s = String(decoding: body, as: UTF8.self)
check(s.hasPrefix("--B\r\nContent-Disposition: form-data; name=\"language\"\r\n\r\nsv\r\n"), "fält först")
check(s.contains("name=\"file\"; filename=\"a.wav\""), "filfält")
check(s.hasSuffix("\r\n--B--\r\n"), "avslutande gräns")

print("Övrigt")
let port = WhisperServer.freePort()
check(port > 1024 && port < 65536, "ledig port (\(port))")
check(formatSeconds(1.234) == "1,23 s", "svenskt decimalkomma")
let sw = Stopwatch(); sw.mark("a"); sw.mark("b")
check(sw.stages.map { $0.name } == ["a", "b"] && sw.total >= 0, "stoppur")

print(failures == 0 ? "\nAlla test gick igenom." : "\n\(failures) test misslyckades.")
exit(failures == 0 ? 0 : 1)
