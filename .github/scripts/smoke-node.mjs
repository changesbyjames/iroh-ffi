// Smoke test for the packed @strangecyan/iroh packages, run from a directory where only the tarballs are installed.
// It proves the loader resolves this platform's addon package, and that a connection accepted without NAT
// traversal carries data. Relays are disabled: the client dials the server's direct addresses.

import pkg from '@strangecyan/iroh'

const { Endpoint, RelayMode } = pkg
const ALPN = Array.from(Buffer.from('iroh-ffi/smoke/0', 'utf8'))
const TIMEOUT_MS = 30_000

async function bind(alpns) {
  const builder = Endpoint.builder()
  builder.applyMinimal()
  builder.relayMode(RelayMode.disabled())
  builder.alpns(alpns)
  return await builder.bind()
}

/** Accept one connection without NAT traversal and echo its first stream back. */
async function echoOnce(server) {
  const incoming = await server.acceptNext()
  if (!incoming) throw new Error('The server closed before a connection arrived')
  const connection = await (await incoming.acceptWithoutNatTraversal()).connect()
  const { send, recv } = await connection.acceptBi()
  await send.writeAll(await recv.readToEnd(1024))
  await send.finish()
  await connection.closed()
}

async function main() {
  const server = await bind([ALPN])
  const client = await bind([])
  try {
    const echoed = echoOnce(server)
    const connection = await client.connect(server.addr(), ALPN)
    const { send, recv } = await connection.openBi()
    await send.writeAll(Array.from(Buffer.from('ping')))
    await send.finish()
    const reply = Buffer.from(await recv.readToEnd(1024)).toString()
    connection.close(0n, [])
    await echoed.catch(() => undefined)
    if (reply !== 'ping') throw new Error(`Expected "ping" back, got "${reply}"`)
    console.log(`ok: ${process.platform}-${process.arch}, echoed over a connection accepted without NAT traversal`)
  } finally {
    await client.close()
    await server.close()
  }
}

const timeout = setTimeout(() => {
  console.error(`smoke test timed out after ${TIMEOUT_MS / 1000}s`)
  process.exit(1)
}, TIMEOUT_MS)
await main()
clearTimeout(timeout)
