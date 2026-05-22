const vscode = require('vscode');
const { LanguageClient, TransportKind, Trace, State } = require('vscode-languageclient/node');
const fs = require('fs');
const path = require('path');

let client;
let lspLogChannel;
let statusItem;

function workspaceRoot() {
    return vscode.workspace.workspaceFolders?.[0]?.uri?.fsPath;
}

function expandConfiguredPath(rawPath, defaultBase) {
    if (typeof rawPath !== 'string' || rawPath.trim().length === 0) {
        return '';
    }

    const trimmed = rawPath.trim();
    let expanded = trimmed.startsWith('~')
        ? path.join(process.env.HOME || '', trimmed.slice(1))
        : trimmed;

    if (!path.isAbsolute(expanded)) {
        expanded = path.join(defaultBase || process.cwd(), expanded);
    }

    return expanded;
}

function activate(context) {
    console.log('Crystal V2 LSP extension is now active');

    // Server options
    // Allow user to configure debug logging via VS Code settings.
    // When crystalV2.lsp.debugLogPath is set, pass CRYSTALV2_LSP_CONFIG pointing to a temp JSON
    // so the server writes detailed logs (including semantic token samples) to that path.
    const config = vscode.workspace.getConfiguration('crystalv2');
    const configuredServerPathRaw = config.get('lsp.serverPath') || '';
    const configuredServerPath = typeof configuredServerPathRaw === 'string' ? configuredServerPathRaw : '';
    const configuredServerArgs = config.get('lsp.serverArgs') || [];
    const serverPath = configuredServerPath.trim().length > 0
        ? expandConfiguredPath(configuredServerPath, workspaceRoot())
        : context.asAbsolutePath('../bin/crystal_v2_lsp');
    const serverArgs = Array.isArray(configuredServerArgs)
        ? configuredServerArgs.filter((arg) => typeof arg === 'string')
        : [];
    const debugLogPathRaw = config.get('lsp.debugLogPath');

    const env = { ...process.env };
    if (debugLogPathRaw && debugLogPathRaw.trim().length > 0) {         
        // Inline JSON config via env var; server already understands CRYSTALV2_LSP_CONFIG
        const tmpConfigPath = `/tmp/crystal_v2_lsp_config_${process.pid}.json`;
        try {
            const base = path.dirname(debugLogPathRaw.trim()) === '.'
                ? path.join(workspaceRoot() || process.cwd(), 'logs')
                : workspaceRoot();
            let expanded = expandConfiguredPath(debugLogPathRaw, base);
            const dir = path.dirname(expanded);
            fs.mkdirSync(dir, { recursive: true });
            fs.writeFileSync(tmpConfigPath, JSON.stringify({ debug_log_path: expanded }));
            env['LSP_DEBUG_LOG'] = expanded; // legacy env for direct path
            env['CRYSTALV2_LSP_CONFIG'] = tmpConfigPath;
        } catch (err) {
            console.warn('Failed to write LSP debug config', err);
        }   
        env['LSP_DEBUG'] = '1';
    }

    const serverOptions = {
        command: serverPath,
        args: serverArgs,
        options: { env },
        transport: TransportKind.stdio
    };

    const traceChannel = vscode.window.createOutputChannel('Crystal V2 LSP Trace');
    lspLogChannel = vscode.window.createOutputChannel('Crystal V2 LSP Messages');
    const traceSetting = config.get('lsp.trace.server') || 'off';
    const traceMap = {
        off: Trace.Off,
        messages: Trace.Messages,
        verbose: Trace.Verbose,
    };
    const traceLevel = traceMap[traceSetting] ?? Trace.Off;

    // Client options
    const clientOptions = {
        documentSelector: [{ scheme: 'file', language: 'crystal' }],
        synchronize: {
            fileEvents: vscode.workspace.createFileSystemWatcher('**/*.cr')
        },      
        traceOutputChannel: traceChannel,
        middleware: {
            didSendRequest: (data) => {
                if (data && data.type === 1) { // RequestMessage
                    try {
                        const body = JSON.parse(data.message);
                        lspLogChannel.appendLine(`--> ${body.method} (${body.id ?? "n/a"})`);
                    } catch (err) {
                        lspLogChannel.appendLine(`--> send (unparsed): ${String(data.message)}`);
                    }
                }
            }
        },
    };  

    // Create and start the language client
    client = new LanguageClient(
        'crystalv2-lsp',
        'Crystal V2 Language Server',
        serverOptions,
        clientOptions
    );

    if (typeof client.onDidChangeState === 'function') {
        client.onDidChangeState((event) => {
            if (event.newState === State.Running) {
                if (typeof client.setTrace === 'function') {
                    client.setTrace(traceLevel);
                } else {
                    try { client.trace = traceLevel; } catch (_) { /* noop */ }
                }
                traceChannel.appendLine(`[client] LSP trace set to ${traceSetting} (state change)`);
                if (statusItem) {
                    statusItem.text = 'Crystal V2 LSP: Ready';
                    statusItem.show();
                }
            }
        });
    } else {
        traceChannel.appendLine('[client] onDidChangeState unavailable; trace channel active but trace level may remain default');
    }

    client.onNotification('crystal/indexing', (params) => {
        const message = params && params.message ? params.message : 'Indexing…';
        if (!statusItem) {
            statusItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 10);
            statusItem.command = undefined;
        }
        statusItem.text = `Crystal V2 LSP: ${message}`;
        statusItem.show();
    });

    client.onNotification('crystal/indexed', () => {
        if (!statusItem) {
            statusItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 10);
        }
        statusItem.text = 'Crystal V2 LSP: Ready';
        statusItem.show();
    });

    client.onNotification((method, params) => {
        // Log all incoming notifications to the message channel
        lspLogChannel.appendLine(`<-- ${method}`);
    });

    // Start the client (this will also launch the server)
    client.start();

    console.log('Crystal V2 LSP client started');
}

function deactivate() {
    if (statusItem) {
        statusItem.dispose();
        statusItem = undefined;
    }
    if (lspLogChannel) {
        lspLogChannel.dispose();
        lspLogChannel = undefined;
    }
    if (!client) {
        return undefined;
    }
    return client.stop();
}

module.exports = {
    activate,
    deactivate
};
