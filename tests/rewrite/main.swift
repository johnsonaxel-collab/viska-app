// Times the rewrite step for each line of a text file with one Ollama model.
// Usage: viska-rewrite <modell> <rader.txt>
import Foundation

let args = Array(CommandLine.arguments.dropFirst())
guard args.count == 2, let text = try? String(contentsOfFile: args[1], encoding: .utf8) else {
    print("Användning: viska-rewrite <modell> <rader.txt>")
    exit(2)
}
let rewriter = Rewriter(model: args[0])
let w = Stopwatch()
rewriter.warmUp()
w.mark("laddning")
print(String(format: "%@: laddad på %.1f s", args[0], w.total))

var times: [Double] = []
for line in text.components(separatedBy: .newlines) where !line.isEmpty {
    let sw = Stopwatch()
    let out: String
    do { out = try rewriter.rewrite(line) } catch { out = "[FEL] \(error.localizedDescription)" }
    sw.mark("omskrivning")
    times.append(sw.total)
    print(String(format: "%.2f s  %@", sw.total, out))
}
let sorted = times.sorted()
print(String(format: "Median %.2f s, max %.2f s", sorted[sorted.count / 2], sorted.last!))
