alias StellarCore.CLI

IO.puts("\n=== Checking Command Status ===\n")

# Check command status for SAT-001
CLI.commands("SAT-001", limit: 5)

IO.puts("\n=== Done ===")
