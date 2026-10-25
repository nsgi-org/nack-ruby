# Nack Specification

This document is the normative contract between bridges and Ruby applications. A host is a program that accepts HTTP requests, owns their memory, and serves them over the [NSGI](https://github.com/nsgi-org/nsgi) protocol. A bridge is the NSGI application between a host and Ruby: it receives each request from the host, invokes the application, and returns the response to the host. An application is the Ruby object defined in section 1.

A bridge is conforming if it provides what this document requires of bridges; an application is conforming if it satisfies what this document requires of applications. Applications written against this contract run on any conforming bridge, and frameworks can target it without depending on any bridge's internals.

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119.

## 1. Application

A Nack application is a Ruby object that responds to `#call` with one argument, the request (section 3). It MUST return a response, the three-element Array `[status, headers, body]` (section 4), or a deferred response (section 4.5). It MAY raise (section 9).

The response is handed over when `#call` returns, normally or by raising, or, for a deferred response, when the responder is called. The host has finished with the response once it has stopped reading the response body and, for a response that switches to a tunnel (section 6), `tunnel` has ended or raised.

When an application is loaded from a file, the file's last expression MUST evaluate to the application object.

## 2. Fields

Message text is free of NUL, LF and CR, and of leading and trailing SP and HTAB.

A field is a `[name, value]` pair whose value is message text and whose name is a lowercase token (RFC 9110, section 5.6.2): one or more ASCII digits, lowercase letters, or bytes among `` !#$%&'*+-.^_`|~ ``. Every field and every other value carrying message text that the bridge provides meets these rules. Every field the application provides MUST meet them, as a pair of `String`s whose bytes are used as-is.

An `Array` of fields carries one field per entry, in message order, and MAY carry several sharing a name. The bridge MUST pass on each field the application provides as a field of its own, in order, and MUST NOT add, merge, or rewrite fields.

## 3. Request

The request object passed to `#call` provides at least these methods:

- `scheme` (`String` or `nil`): The scheme of the hop the host terminated, lowercase. `nil` when the host reports none. A host that terminated a scheme other than `http` or `https` reports it through `variable` under `request.scheme`, and a bridge that cannot obtain it there MUST raise rather than report `nil`.
- `http_version` (`String` or `nil`): One of `HTTP/1.0`, `HTTP/1.1`, `HTTP/2` and `HTTP/3`. `nil` when the host reports no version.
- `remote_address` (`String` or `nil`): The transport peer that opened the connection. IPv4 in dotted-quad form; IPv6 in the lowercase zero-compressed form of RFC 5952, with `%` and the decimal zone index appended when the host reports a nonzero one; a UNIX domain socket as `unix:` followed by the path bytes, or `unix:` alone when it is unnamed. The IP forms are `Encoding::US_ASCII` and the `unix:` form `Encoding::BINARY`. `nil` when the host reports no peer, and when it reports one whose family it cannot represent.
- `remote_port` (`Integer` or `nil`): The port of `remote_address`. `nil` when `remote_address` is `nil` or has no port.
- `local_address` (`String` or `nil`): The address the connection was accepted on, in the forms of `remote_address`.
- `local_port` (`Integer` or `nil`): The port of `local_address`, as `remote_port` is of `remote_address`.
- `connection` (`Hash`): Per-connection state (section 3.1).
- `request_method` (`IO::Buffer`): The method, e.g. `GET`.
- `protocol` (`IO::Buffer` or `nil`): The `:protocol` of an extended CONNECT request (RFC 8441), e.g. `websocket`. `nil` when the request carries none.
- `authority` (`IO::Buffer` or `nil`): The authority as received, of the form `host [ ":" port ]` (RFC 3986), taken from the request target in absolute or authority form and otherwise from `:authority` or `Host`. `nil` when the request conveys none.
- `path` (`IO::Buffer` or `nil`): The path as received, neither percent-decoded nor with dot segments removed, e.g. `/api/v1`. `*` for a server-wide OPTIONS request, and otherwise `/` for a request target in absolute form with an empty path. `nil` for a CONNECT request whose target is the authority alone.
- `query` (`IO::Buffer` or `nil`): The query as received and not percent-decoded, without the leading `?`. `nil` when the request carries none.
- `headers` (`Array` of `[IO::Buffer, IO::Buffer]`): The header fields, except that the `cookie` fields of an HTTP/2 or HTTP/3 request are joined into one, separated by `; `. They carry no `host` (reported by `authority`), no `content-length` (reported by `content_length`), no `transfer-encoding` (already decoded), and no pseudo-header.
- `content_length` (`Integer` or `nil`): The content length the request declared, which the application MUST NOT treat as the number of bytes `body` will deliver. `nil` when the request declared none.
- `variable(name)` (`IO::Buffer` or `nil`): Connection and server metadata the host reports under a lowercase, dot-separated `String` name compared bytewise, e.g. `tls.version`, `server.software`, `proxy_protocol.src_addr`. Header fields are not available here. A recognized name with an empty value returns an empty buffer, and `nil` means the host does not recognize the name. A lookup the host reports as failed MUST raise.
- `body`: The request content (section 3.2).
- `trailers` (`Array` of `[IO::Buffer, IO::Buffer]`): The trailer fields (section 3.3).
- `inform(status, headers)`: Sends an interim response (section 5).
- `tunnel`: The bytes the client sends through a tunnel (section 6).

A bridge MUST NOT derive `scheme` from `X-Forwarded-Proto`, nor `remote_address` or `remote_port` from `X-Forwarded-For` or `Forwarded`.

### 3.1. Connection

`connection` returns a `Hash` the application may store per-connection state in. The bridge MUST return the same `Hash` for every request that arrived on one connection, MUST NOT return one `Hash` for two different connections, and MUST discard it once the connection has ended. A host that terminates no transport connections reports every request as arriving on a connection of its own.

Requests that arrived on one connection MAY be in flight at the same time (section 8).

### 3.2. Body

`body` returns a stream delivering the request content, never `nil`. A stream provides at least:

- `read` (`IO::Buffer` or `nil`): The next chunk, in the order the bytes arrived. `nil` once the stream has ended, raising once it has failed (section 3.4).

`#read` waits for one of these and MUST NOT report that no bytes are available at this moment, the host's wakeups being the bridge's to use. Each call moves past one chunk rather than returning a requested number of bytes, and chunk boundaries carry no meaning.

`body` ends on the first `#read` for a request carrying no content. The application MAY respond with it unread.

### 3.3. Trailers

`trailers` returns the trailer fields once `body` has ended, and an empty Array for a request carrying none.

### 3.4. Failures

`#read` on a failed stream, `trailers` called before `body` has ended, and a failed `inform` (section 5) MUST raise a `StandardError` whose `#condition` returns the Symbol a table in this document gives the NSGI status reporting the failure, or `nil` for a failure no table names. NSGI defines what each status means. The exception's class is the bridge's own.

| Symbol | NSGI status |
| --- | --- |
| `:body_terminated` | `NSGI_REQUEST_BODY_ERROR_TERMINATED` |
| `:body_malformed` | `NSGI_REQUEST_BODY_ERROR_MALFORMED` |
| `:body_too_large` | `NSGI_REQUEST_BODY_ERROR_TOO_LARGE` |
| `:body_timeout` | `NSGI_REQUEST_BODY_ERROR_TIMEOUT` |
| `:trailers_incomplete` | `NSGI_REQUEST_TRAILERS_ERROR_INCOMPLETE` |

## 4. Response

### 4.1. Status

`status` is the final response's and MUST be an `Integer` in `200..599`, or 101 for a response that switches to a tunnel (section 6).

### 4.2. Headers

`headers` MUST be an `Array` of fields and MUST NOT carry a field that governs the connection rather than the message: `connection`, `keep-alive`, `proxy-connection`, `te`, `transfer-encoding`, or, other than on a 101, `upgrade`. The host supplies whatever of these its connection needs.

`headers` MAY carry a `content-length` whose value is a decimal number (RFC 9110, section 8.6) when the application knows the content's length, and the body MUST then produce exactly that many bytes. A response to HEAD MAY instead declare the length a response to the same request made with GET would have had, and a 304 the length a 200 to the same request would have had. The host leaves out any `content-length` that a 101, a 204, or a 2xx to CONNECT carries.

### 4.3. Body

`body` MUST be `nil` (empty), a `String` (its bytes are used as-is; encoding is not interpreted), an `IO::Buffer` (its backing bytes are used without an intermediate String), or an object responding to `#each`.

The bridge enumerates such a body at most once: it calls `#each` with a block, and the body yields each chunk to that block as a `String` or an `IO::Buffer`. The block MAY take arbitrarily long to return, which is how the host's backpressure reaches the application. The bridge MUST NOT pass on a zero-length chunk. A response to HEAD, a 204 and a 304 carry no content, so the bridge need not enumerate their bodies.

The bridge MAY stop enumerating before the body is complete, so a body with side effects MUST tolerate being abandoned part-way. The bridge MUST call `#close` on a body that responds to it once it is finished with the body, whether or not it enumerated the body to completion.

### 4.4. Trailers

A body that responds to `#each` MAY also respond to `#trailers`, returning an `Array` of fields. The bridge calls it at most once, after `#each` has returned without being stopped and before `#close`. The host transmits a trailer section only where the message framing can carry one, and the application MUST NOT send a field in it whose definition does not permit it there (RFC 9110, section 6.5.1).

### 4.5. Deferred response

A deferred response is an object responding to `#call` with one argument. The bridge MUST invoke it exactly once, passing a responder, and MUST NOT wait for the responder before returning control to the host.

The responder is a callable taking one argument, the three-element Array of section 4. The application MUST call it exactly once; a second call MUST raise, and the first response stands.

The host MAY stop wanting the response. The bridge MAY tell the application, and MAY have `body` and `tunnel` raise; the application MUST still call the responder exactly once.

## 5. Interim responses

`inform(status, headers)` sends an interim response ahead of the final one. `status` MUST be an `Integer` in `100..199` other than 101, which only a final response carries, and `headers` an `Array` of fields carrying none that section 4.2 forbids, of which the host leaves out any `content-length`.

`inform` returns `true` when the host accepts the interim response, and `false` when it declines it, as it MAY for any. The host transmits the accepted ones ahead of the final response in the order of the calls, and nothing for any other.

A failed `inform` raises as section 3.4 describes, with one of:

| Symbol | NSGI status |
| --- | --- |
| `:inform_invalid` | `NSGI_INFORM_ERROR_INVALID` |
| `:inform_responded` | `NSGI_INFORM_ERROR_RESPONDED` |

## 6. Tunnels

A final response can switch the exchange to a tunnel, a bidirectional byte stream that is no longer HTTP, such as a WebSocket. Two responses switch:

- A 101 to an HTTP/1.1 request carrying `upgrade`, with an `upgrade` naming a protocol the request listed.
- A 2xx to a CONNECT request on any version, including an extended CONNECT request.

The host passes a CONNECT request to the application only when configured to, and otherwise answers 501.

`tunnel` returns a stream (section 3.2), never `nil`, delivering the bytes the client sends after the request message and ending when the client closes its sending direction. The switching response's body carries the bytes sent to the client. `body` still delivers the request's own content, of which a CONNECT request has none.

Each direction closes on its own: the response body completing closes the host's sending direction, `tunnel` ending reports that the client closed its own, and a response body failure aborts both. The host keeps the response until `tunnel` has ended or raised, so the application can go on reading after closing its own direction.

The tunnel makes no progress until the response has been handed over, so the application reads it from the response body or a Fiber of its own, not from `#call`.

A failed `tunnel` raises as section 3.4 describes, with one of:

| Symbol | NSGI status |
| --- | --- |
| `:tunnel_not_switched` | `NSGI_TUNNEL_ERROR_NOT_SWITCHED` |
| `:tunnel_terminated` | `NSGI_TUNNEL_ERROR_TERMINATED` |
| `:tunnel_timeout` | `NSGI_TUNNEL_ERROR_TIMEOUT` |

## 7. Memory

Request accessors stay usable for these windows:

- `body`, `trailers`, `tunnel`, `variable` and `inform`, and the streams `body` and `tunnel` return, until the host has finished with the response, so the request and response bodies can stream at once.
- Every other accessor, until `#call` returns.

Every buffer a request accessor returns is a read-only view over host memory. The application MUST NOT attempt to free, resize, or write through one, MUST copy any data it needs beyond the buffer's validity, and MUST NOT hand one back as part of a response. A buffer is valid while its accessor is usable, and no longer than:

- for `variable`, until the next `variable` call for the same request;
- for `trailers`, until the next `trailers` call for the same request;
- for a chunk, until the next `#read` from the same stream.

Using an accessor, or a buffer, after its window has closed MUST NOT expose host memory; the bridge SHOULD raise instead. Buffers MAY be created lazily. Values that are not buffers are the bridge's own and outlive the request.

Response memory handed to the host is owned by the bridge, never by Ruby: bridges MUST copy Ruby-provided bytes into memory that survives garbage collection and compaction, and MUST release it according to NSGI's lifetime rules. An `IO::Buffer` the application supplies in a response MUST remain valid until the bridge has finished with it.

## 8. Concurrency

A bridge MAY be invoked concurrently by its host. A conforming bridge serializes application execution into a single Ruby execution context but MAY multiplex concurrent requests onto Fibers via a `Fiber::Scheduler`, so:

- The application MUST be fiber-reentrant: whenever it sleeps or waits on IO, another request may run before the wait returns. A `#read` is such a wait. Shared mutable state, including `connection`, needs the same care as under any cooperative scheduler.
- The application MUST NOT assume two requests never interleave, and MUST NOT assume they run on different threads (thread-locals are shared; fiber-locals (`Thread#[]`) are per-request under fiber multiplexing).
- Blocking a request without going through a scheduler-aware primitive (e.g. spinning, or C extensions that block the thread) stalls every in-flight request; applications SHOULD avoid it.
- A deferred response releases the execution context when `#call` returns.

The bridge MAY allow the application to supply its own conforming `Fiber::Scheduler`; the application contract itself never depends on which scheduler runs.

## 9. Errors

The bridge MUST catch any exception, including `Exception` subclasses outside `StandardError`, and MUST NOT let one crash or unwind into the host.

- Bridge overload: the bridge MAY reject new requests with a 503 before dispatching them to the application.
- Exception from `#call`, or from a deferred response before the responder is called: the bridge responds 500.
- Request body failure the application did not rescue: the bridge MAY respond with the HTTP status matching the failure (section 3.4) rather than 500.
- Deferred response never completed: the bridge MAY impose a deadline of its own and respond 500.
- Malformed response, including a 101 that does not switch to a tunnel: the bridge SHOULD respond 500.
- Response body failure, including `#trailers` raising or returning a malformed trailer section: the bridge MUST report the failure to the host, which leaves the message incomplete, and MUST NOT attempt a 500.
