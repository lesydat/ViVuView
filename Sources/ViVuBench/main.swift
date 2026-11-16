import Foundation
import ViVuCore

// vivu-bench: windowless timing of the decode paths (docs/TECH_SPEC.md §11.2).
// Measuring commands are added from milestone M0.5 on.

let usage = """
usage: vivu-bench <command>

commands:
  version    print the bench version
"""

let args = CommandLine.arguments.dropFirst()
switch args.first {
case "version":
    print("vivu-bench 0.1.0 (\(Tuning.bundleID))")
case nil, "help", "-h", "--help":
    print(usage)
default:
    FileHandle.standardError.write(Data("unknown command: \(args.first!)\n\n\(usage)\n".utf8))
    exit(1)
}
