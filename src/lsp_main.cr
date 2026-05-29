require "./compiler/lsp/server"

# LSP Server entry point
# Usage: adamas_lsp
# Communicates via stdin/stdout using LSP protocol

server = Adamas::Compiler::LSP::Server.new
server.start
