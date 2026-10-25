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
      == "https://huggingface.co/KBLab/kb-whisper-small/resolve/3564d61a42fc210ceaa55a22a96dd64478959c78/ggml-model-q5_0.bin",
      "nedladdningen är låst till en version")
check(ModelCatalog.all.allSatisfy { $0.sha256.count == 64 && $0.revision.count == 40 }, "alla modeller har fingeravtryck")

print("Checksum")
let tmpFile = FileManager.default.temporaryDirectory.appendingPathComponent("viska-sha-test")
try? Data("abc".utf8).write(to: tmpFile)
check(Checksum.sha256(of: tmpFile) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "SHA-256 stämmer")
check(Checksum.sha256(of: URL(fileURLWithPath: "/finns/inte")) == nil, "saknad fil ger nil")
try? FileManager.default.removeItem(at: tmpFile)

print("Talmotorns adress")
let ws = WhisperServer(binary: "/finns/inte")
check(ws.endpoint("health").path == "/health" || ws.secretPath.isEmpty, "tom hemlig väg före start")

print("RewriteLog")
try? FileManager.default.removeItem(at: RewriteLog.url)
for i in 1...(RewriteLog.maxLines + 10) { RewriteLog.append(raw: "rad \(i)\nmed radbrytning", error: "test") }
let logLines = ((try? String(contentsOf: RewriteLog.url, encoding: .utf8)) ?? "").split(separator: "\n")
check(logLines.count == RewriteLog.maxLines, "loggen behåller bara de senaste \(RewriteLog.maxLines)")
check(logLines.last?.hasSuffix("rad \(RewriteLog.maxLines + 10) med radbrytning") == true, "senaste raden sist, utan radbrytning")

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

print("RewriteGuard")
check(RewriteGuard.tidy("\"Hej Anna.\"") == "Hej Anna.", "tar bort citattecken")
check(RewriteGuard.tidy("Text: Hej.") == "Hej.", "tar bort ekat Text:")
check(RewriteGuard.problem(raw: "eh hej typ", rewritten: "Hej.") == nil, "kortare text godkänns")
check(RewriteGuard.problem(raw: "hej", rewritten: "") != nil, "tomt svar stoppas")
check(RewriteGuard.problem(raw: "kan du skicka filen",
      rewritten: "Kan du skicka filen? Jag behöver den till mötet på måndag klockan nio, tack så mycket!") != nil,
      "påhittad fortsättning stoppas")
check(RewriteGuard.problem(raw: "vad är klockan", rewritten: "Här är svaret: tolv.") != nil,
      "svar i stället för omskrivning stoppas")

print("Prompts")
check(Prompts.stripComments("// not\nRegel\n  // inte\nRegel 2") == "Regel\nRegel 2", "kommentarer tas bort")
check(Prompts.load(Prompts.rewriteFile).contains("Hitta aldrig på"), "standardprompten skapas")
check(FileManager.default.fileExists(atPath: Prompts.url(Prompts.rewriteFile).path), "promptfilen finns på disk")

print("Reserv utan Ollama")
let dead = Rewriter(client: OllamaClient(base: URL(string: "http://127.0.0.1:1")!), model: "x")
let t0 = Date()
var gotUnavailable = false
do { _ = try dead.rewrite("hej") } catch RewriteError.unavailable { gotUnavailable = true } catch {}
check(gotUnavailable, "kastar unavailable när Ollama saknas")
check(Date().timeIntervalSince(t0) < 1, "ger upp på under 1 s")
check(dead.client.models() == nil, "models() är nil när Ollama saknas")

print(failures == 0 ? "\nAlla test gick igenom." : "\n\(failures) test misslyckades.")
exit(failures == 0 ? 0 : 1)
