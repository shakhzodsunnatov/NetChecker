#!/usr/bin/env node
// NetChecker MCP Bridge
// Forwards MCP tool calls → NetChecker HTTP server on device
// Zero dependencies — pure Node.js built-ins
//
// Auto-discovery: tries localhost:9876 first (simulator/iproxy),
// then NETCHECKER_URL env var (real device Wi-Fi IP)

const URLS = [
    'http://localhost:9876',
    process.env.NETCHECKER_URL
].filter(Boolean);

let NETCHECKER_URL = URLS[0];

// ─── MCP Protocol over stdio ──────────────────────────────────────────────────

process.stdin.setEncoding('utf8');
let buffer = '';

process.stdin.on('data', (chunk) => {
    buffer += chunk;
    const lines = buffer.split('\n');
    buffer = lines.pop() || '';
    for (const line of lines) {
        if (line.trim()) {
            try { handleMessage(JSON.parse(line)); } catch (_) {}
        }
    }
});

async function handleMessage(msg) {
    const { id, method, params } = msg;

    switch (method) {
        case 'initialize':
            respond(id, {
                protocolVersion: '2024-11-05',
                capabilities: { tools: {} },
                serverInfo: { name: 'netchecker', version: '1.0.0' }
            });
            break;

        case 'notifications/initialized':
            break; // no response needed

        case 'tools/list':
            respond(id, { tools: TOOLS });
            break;

        case 'tools/call':
            await handleToolCall(id, params);
            break;

        default:
            if (id !== undefined) respond(id, null);
    }
}

// ─── Tool Definitions ─────────────────────────────────────────────────────────

const TOOLS = [
    {
        name: 'netchecker_log',
        description: 'Send a structured log entry to NetChecker on the iOS/macOS device. Use this to track API calls, file operations, code changes, test runs, and other AI tool actions.',
        inputSchema: {
            type: 'object',
            properties: {
                operationType: {
                    type: 'string',
                    enum: ['apiCall', 'fileRead', 'fileWrite', 'fileDelete',
                           'codeGeneration', 'codeRefactor', 'codeFix',
                           'testExecution', 'testAssertion',
                           'buildStart', 'buildComplete', 'buildError',
                           'commandExecution', 'schemaValidation', 'custom'],
                    description: 'Type of operation'
                },
                url: { type: 'string', description: 'URL (for apiCall operations)' },
                method: { type: 'string', description: 'HTTP method (GET, POST, etc.)' },
                statusCode: { type: 'number', description: 'HTTP response status code' },
                expectedStatusCode: { type: 'number', description: 'Expected status code for validation' },
                expectedFields: {
                    type: 'array',
                    items: { type: 'string' },
                    description: 'Expected JSON fields in response body'
                },
                severity: {
                    type: 'string',
                    enum: ['debug', 'info', 'warning', 'error', 'critical'],
                    default: 'info'
                },
                sessionId: { type: 'string', description: 'Session identifier' },
                flowId: { type: 'string', description: 'Flow ID to group related operations' },
                sequenceNumber: { type: 'number', description: 'Order within the flow' },
                tags: { type: 'array', items: { type: 'string' } },
                description: { type: 'string', description: 'Human-readable description of the operation' }
            },
            required: ['operationType']
        }
    },
    {
        name: 'netchecker_flow_start',
        description: 'Start a named flow in NetChecker to group a set of related operations (e.g. "Implementing login feature"). Call this at the beginning of a task.',
        inputSchema: {
            type: 'object',
            properties: {
                flowId: { type: 'string', description: 'Unique flow identifier' },
                flowName: { type: 'string', description: 'Human-readable flow name' },
                flowDescription: { type: 'string', description: 'What this flow implements' },
                sessionId: { type: 'string' }
            },
            required: ['flowId', 'flowName']
        }
    },
    {
        name: 'netchecker_flow_end',
        description: 'End a flow in NetChecker. Call this when the task is complete. The app will show the full timeline and offer to generate Swift tests.',
        inputSchema: {
            type: 'object',
            properties: {
                flowId: { type: 'string' },
                status: { type: 'string', enum: ['completed', 'failed'], default: 'completed' }
            },
            required: ['flowId']
        }
    },
    {
        name: 'netchecker_status',
        description: 'Check if NetChecker MCP server is running on the device',
        inputSchema: { type: 'object', properties: {} }
    }
];

// ─── Tool Handlers ────────────────────────────────────────────────────────────

async function handleToolCall(id, params) {
    const { name, arguments: args } = params;

    try {
        let result;

        if (name === 'netchecker_log') {
            const body = {
                operationType: args.operationType,
                source: { toolName: 'claude-code', sessionId: args.sessionId || 'claude-code-session' },
                severity: args.severity || 'info',
                tags: args.tags || []
            };

            if (args.flowId) {
                body.flowContext = {
                    flowId: args.flowId,
                    ...(args.sequenceNumber !== undefined && { sequenceNumber: args.sequenceNumber })
                };
            }

            // Build payload based on operation type
            if (args.url) {
                body.payload = {
                    type: 'networkCall',
                    url: args.url,
                    method: args.method || 'GET',
                    ...(args.statusCode !== undefined && { statusCode: args.statusCode })
                };
            } else if (args.description) {
                body.payload = { type: 'raw', data: args.description };
            }

            // Add expectations if provided
            if (args.expectedStatusCode || args.expectedFields) {
                body.expectations = {};
                if (args.expectedStatusCode) body.expectations.expectedStatusCode = args.expectedStatusCode;
                if (args.expectedFields) body.expectations.expectedFields = args.expectedFields;
            }

            result = await httpPost(`${NETCHECKER_URL}/log`, body);

        } else if (name === 'netchecker_flow_start') {
            result = await httpPost(`${NETCHECKER_URL}/flow/start`, {
                flowId: args.flowId,
                flowName: args.flowName,
                ...(args.flowDescription && { flowDescription: args.flowDescription }),
                source: { toolName: 'claude-code', sessionId: args.sessionId || 'claude-code-session' }
            });

        } else if (name === 'netchecker_flow_end') {
            result = await httpPost(`${NETCHECKER_URL}/flow/end`, {
                flowId: args.flowId,
                status: args.status || 'completed'
            });

        } else if (name === 'netchecker_status') {
            result = await httpGet(`${NETCHECKER_URL}/status`);
        }

        respond(id, {
            content: [{ type: 'text', text: JSON.stringify(result, null, 2) }]
        });

    } catch (err) {
        // Auto-fallback: try next URL if current one fails
        const currentIdx = URLS.indexOf(NETCHECKER_URL);
        const nextIdx = (currentIdx + 1) % URLS.length;
        if (URLS.length > 1 && URLS[nextIdx] !== NETCHECKER_URL) {
            NETCHECKER_URL = URLS[nextIdx];
            return handleToolCall(id, params); // retry with next URL
        }

        respond(id, {
            content: [{ type: 'text', text: `NetChecker unreachable at ${URLS.join(', ')}.\nMake sure the app is running and MCP server is started.` }],
            isError: true
        });
    }
}

// ─── HTTP Helpers ─────────────────────────────────────────────────────────────

function httpPost(url, body) {
    return new Promise((resolve, reject) => {
        const http = require('http');
        const data = JSON.stringify(body);
        const u = new URL(url);

        const req = http.request({
            hostname: u.hostname,
            port: u.port || 80,
            path: u.pathname,
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Content-Length': Buffer.byteLength(data)
            }
        }, (res) => {
            let out = '';
            res.on('data', c => out += c);
            res.on('end', () => {
                try { resolve(JSON.parse(out)); } catch { resolve({ ok: true }); }
            });
        });

        req.on('error', reject);
        req.setTimeout(5000, () => req.destroy(new Error('timeout after 5s')));
        req.write(data);
        req.end();
    });
}

function httpGet(url) {
    return new Promise((resolve, reject) => {
        const http = require('http');
        const u = new URL(url);

        const req = http.get({
            hostname: u.hostname,
            port: u.port || 80,
            path: u.pathname
        }, (res) => {
            let out = '';
            res.on('data', c => out += c);
            res.on('end', () => {
                try { resolve(JSON.parse(out)); } catch { resolve({ raw: out }); }
            });
        });

        req.on('error', reject);
        req.setTimeout(5000, () => req.destroy(new Error('timeout after 5s')));
    });
}

function respond(id, result) {
    process.stdout.write(JSON.stringify({ jsonrpc: '2.0', id, result }) + '\n');
}
