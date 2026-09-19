# Nack Specification

This document is the normative contract between bridges and Ruby applications. A host is a program that accepts HTTP requests and owns their memory, e.g. an [NSGI](https://github.com/nsgi-org/nsgi) web server. A bridge is the layer between a host and Ruby: it receives each request from the host, invokes the application, and returns the response to the host. An application is the Ruby object defined in section 1.

A bridge is conforming if it provides what this document requires of bridges; an application is conforming if it satisfies what this document requires of applications. Applications written against this contract run on any conforming bridge, and frameworks can target it without depending on any bridge's internals.

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119.

## 1. Application

A Nack application is a Ruby object that responds to `#call` with one argument, the request. It MUST return a three-element Array, `[status, headers, body]`, whose elements section 3 defines. An application MAY instead return the deferred response of section 4.

When an application is loaded from a file, the file's last expression MUST evaluate to the application object.

The application MAY raise; the bridge MUST catch any exception (including `Exception` subclasses outside `StandardError`) and turn it into a 500 response. An exception MUST NOT crash or unwind into the host.

## 2. Request

The request object passed to `#call` provides at least these methods:

- `scheme` (`String` or `nil`): The scheme of the hop the host terminated, lowercase. `nil` when the host reports none. A host that terminated a scheme other than `http` or `https` reports it through `variable` under `request.scheme`, and a bridge that cannot obtain it there MUST raise rather than report `nil`.
- `http_version` (`String` or `nil`): One of `HTTP/1.0`, `HTTP/1.1`, `HTTP/2` and `HTTP/3`. A bridge MUST NOT produce another spelling. `nil` when the host reports no version.
- `remote_address` (`String` or `nil`): The transport peer that opened the connection. IPv4 in dotted-quad form; IPv6 in the lowercase zero-compressed form of RFC 5952, with `%` and the decimal zone index appended when the host reports a nonzero one; a UNIX domain socket as `unix:` followed by the path bytes, or `unix:` alone when it is unnamed. The IP forms are `Encoding::US_ASCII` and the `unix:` form `Encoding::BINARY`. `nil` when the host reports no peer, and when it reports one whose family it cannot represent.
- `remote_port` (`Integer` or `nil`): The port of `remote_address`. `nil` when `remote_address` is `nil` or has no port.
- `local_address` (`String` or `nil`): The address the connection was accepted on, in the forms `remote_address` uses.
- `local_port` (`Integer` or `nil`): The port of `local_address`, under the rule `remote_port` follows.
- `connection` (`Hash`): Per-connection state, described in section 2.1.
- `request_method` (`IO::Buffer`): HTTP method bytes, e.g. `GET`.
- `authority` (`IO::Buffer` or `nil`): Authority bytes as received, including any port, taken from the request target when it is in absolute form and otherwise from `:authority` or `Host`, and never carrying userinfo. `nil` when the request conveys no authority.
- `path` (`IO::Buffer`): Path component bytes as received, e.g. `/api/v1`, not percent-decoded.
- `query` (`IO::Buffer` or `nil`): Query bytes as received, without the leading `?` and not percent-decoded. `nil` when the request carries none.
- `headers` (`Array` of `[IO::Buffer, IO::Buffer]`): Header name/value pairs, in host order. Every name is lowercase and carries no colon. The Array carries no `host` entry (reported by `authority`), no `content-length` (reported by `content_length`), no `transfer-encoding` (already decoded), and no pseudo-header.
- `content_length` (`Integer` or `nil`): The body length the request declared. An application MUST NOT treat it as the number of bytes `body` will produce. `nil` when the request declared none.
- `variable(name)` (`IO::Buffer` or `nil`): Host connection and server metadata, under a lowercase, dot-separated `String` name compared bytewise, e.g. `tls.version`, `server.software`, `proxy_protocol.src_addr`. Request headers are not available here. A name the host recognizes with an empty value returns an empty buffer; `nil` means the host does not recognize it. A lookup the host reports as failed MUST raise.
- `body`: The request body, read one chunk at a time, described in section 2.2.

A bridge MUST NOT derive `scheme` from `X-Forwarded-Proto`, nor `remote_address` or `remote_port` from `X-Forwarded-For` or `Forwarded`.

Every value carrying HTTP message text (`request_method`, `authority`, `path`, `query`, every header name and value, and every value `variable` returns) is free of NUL, LF and CR, and of leading and trailing SP and HTAB.

### 2.1. Connection

`connection` returns a `Hash` the application may store per-connection state in. The bridge MUST return the same `Hash` for every request that arrived on one connection, MUST NOT return one `Hash` for two different connections, and MUST discard it once the connection has ended. A host that terminates no transport connections reports every request as arriving on a connection of its own.

Requests that arrived on one connection MAY be in flight at the same time, so the `Hash` needs the care section 5 requires of any shared mutable state.

### 2.2. Body

`body` returns an object that delivers the request body in chunks. It is never `nil`: a request carrying no body reports the end on the first `#read`. The object provides at least:

- `read` (`IO::Buffer` or `nil`): The next chunk of body bytes, in the order they arrived. `nil` once the body is complete.

`#read` returns once a chunk is available, the body is complete, or the body has failed. It MUST NOT report that no bytes are available at this moment. Each call moves past one chunk rather than returning a requested number of bytes, and chunk boundaries carry no meaning.

A body that has failed MUST raise, and the bridge SHOULD raise a distinct exception for each condition the host distinguishes. Once `#read` has reported the end or raised, every later `#read` MUST report that same outcome.

An application MAY respond with the body unread.

### 2.3. Buffers

All buffers are read-only views over memory owned by the host:

- The application MUST NOT attempt to free, resize, or write through them.
- A buffer from `variable` is valid until the next `variable` call for the same request, and a body chunk until the next `#read` from the same body. Every other buffer is valid for as long as the request is.
- They are request-scoped: the bridge MUST invalidate every handed-out buffer when the request completes, which is when `#call` returns (normally or by raising), or, for a deferred response, when the responder is called. The application MUST copy any data it needs beyond that, and MUST NOT hand one back as part of a response body.
- Accessing a buffer, or a request accessor, after the request completed MUST NOT expose host memory. The bridge SHOULD raise instead.

Buffers MAY be created lazily. Values that are not buffers are the bridge's own and outlive the request.

## 3. Response

### 3.1. Status

`status` MUST be an `Integer` in `100..599`.

### 3.2. Headers

`headers` MUST be an `Array` of `[name, value]` pairs; each name and value MUST be a `String`. A name MUST NOT contain uppercase ASCII characters, a colon, or any byte in `0x00..0x20` or `0x7F..0xFF`. Values are treated as raw bytes, MUST NOT contain NUL, CR or LF, and MUST NOT begin or end with SP or HTAB; an empty value is permitted.

`headers` MUST NOT carry `transfer-encoding`. It MAY carry `content-length` when the application knows the body's length, in which case the body MUST produce exactly that many bytes.

Duplicate names are permitted. The bridge MUST preserve duplicates and the relative order of pairs sharing a name (e.g. multiple `set-cookie` headers), MAY reorder pairs with different names, and MUST NOT add, merge, or rewrite headers.

### 3.3. Body

`body` MUST be `nil` (empty), a `String` (its bytes are used as-is; encoding is not interpreted), an `IO::Buffer` (its backing bytes are used without an intermediate String), or an object responding to `#each`.

The bridge enumerates such a body exactly once: it calls `#each` with a block, and the body yields each chunk to that block as a `String` or an `IO::Buffer`. The block MAY take arbitrarily long to return, which is how the host's backpressure reaches the application. The bridge MUST NOT pass on a zero-length chunk.

The bridge MAY stop enumerating before the body is complete, so a body with side effects MUST tolerate being abandoned part-way. The bridge MUST call `#close` on a body that responds to it once it is finished with the body, including when it stopped early.

An `IO::Buffer` the application supplies MUST remain valid until the bridge has finished with it, and MUST NOT be a request-scoped buffer (section 2.3).

### 3.4. Ownership

Response memory handed to the host is owned by the bridge, never by Ruby: bridges MUST copy Ruby-provided bytes into memory that survives garbage collection and compaction, and MUST release it according to the host protocol's lifetime rules.

## 4. Deferred response

A deferred response is an object responding to `#call` with one argument. The bridge MUST invoke it exactly once, passing a responder, and MUST NOT wait for the responder before returning control to the host.

The responder is a callable taking one argument, the three-element Array of section 3. The application MUST call it exactly once; a second call MUST raise, and the first response stands.

The request completes when the responder is called, so section 2.3's invalidation happens then. Until then `body` and `variable` stay usable, while every other accessor and every buffer already handed out is invalidated when `#call` returns.

The host MAY stop wanting the response. The bridge MAY tell the application, and MAY have `body` raise; the application MUST still call the responder exactly once.

## 5. Concurrency

A bridge MAY be invoked concurrently by its host. A conforming bridge serializes application execution into a single Ruby execution context but MAY multiplex concurrent requests onto Fibers via a `Fiber::Scheduler`, so:

- The application MUST be fiber-reentrant: whenever it sleeps or waits on IO, another request may run before the wait returns. Reading the request body is such a wait. Shared mutable state needs the same care as under any cooperative scheduler.
- The application MUST NOT assume two requests never interleave, and MUST NOT assume they run on different threads (thread-locals are shared; fiber-locals (`Thread#[]`) are per-request under fiber multiplexing).
- Blocking a request without going through a scheduler-aware primitive (e.g. spinning, or C extensions that block the thread) stalls every in-flight request; applications SHOULD avoid it.
- A deferred response releases the execution context when `#call` returns.

The bridge MAY allow the application to supply its own conforming `Fiber::Scheduler`; the application contract itself never depends on which scheduler runs.

## 6. Errors

- Application exception from `#call`, or from a deferred response before the responder is called: 500 response, request buffers still invalidated, host never crashes.
- Malformed response: the bridge MUST NOT crash; it SHOULD respond 500.
- Request body failure the application did not rescue: the bridge MAY respond with the status matching the condition the host reported, rather than 500.
- Response body failure: the bridge MUST report the failure to the host, and MUST NOT attempt a 500.
- Deferred response never completed: the bridge MAY impose a deadline of its own and respond 500.
- Bridge overload: the bridge MAY reject new requests with a 503 before dispatching them to the application.
