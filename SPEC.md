# Nack Specification

This document is the normative contract between bridges and Ruby applications. A host is a program that accepts HTTP requests and owns their memory, e.g. an [NSGI](https://github.com/nsgi-org/nsgi) web server. A bridge is the layer between a host and Ruby: it receives each request from the host, invokes the application, and returns the response to the host. An application is the Ruby object defined in section 1.

A bridge is conforming if it provides what this document requires of bridges; an application is conforming if it satisfies what this document requires of applications. Applications written against this contract run on any conforming bridge, and frameworks can target it without depending on any bridge's internals.

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119.

## 1. Application

A Nack application is a Ruby object that responds to `call` with one argument, the request. It MUST return a three-element Array:

```ruby
[status, headers, body]
```

When an application is loaded from a file, the file's last expression MUST evaluate to the application object.

The application MAY raise; the bridge MUST catch any exception (including `Exception` subclasses outside `StandardError`) and turn it into a 500 response. An exception MUST NOT crash or unwind into the host.

## 2. Request

The request object passed to `call` provides at least these methods:

| Method | Returns | Meaning |
| ---- | ---- | ---- |
| `method` | `IO::Buffer` | HTTP method bytes (e.g. `GET`) |
| `path` | `IO::Buffer` | Path component bytes (e.g. `/api/v1`) |
| `query` | `IO::Buffer` or `nil` | Query bytes without the leading `?`; `nil` when absent |
| `headers` | `Array` of `[IO::Buffer, IO::Buffer]` | Header name/value pairs, in host order |
| `body` | `IO::Buffer` or `nil` | Request body bytes; `nil` when empty |

All buffers are read-only views over memory owned by the host:

- The application MUST NOT attempt to free, resize, or write through them.
- They are request-scoped: the bridge MUST invalidate every handed-out buffer when `call` returns (normally or by raising), before control returns to the host. The application MUST copy any data it needs beyond the request.
- Accessing a buffer, or a request accessor, after the request completed MUST NOT expose host memory. The bridge SHOULD raise instead.

Buffers MAY be created lazily.

## 3. Response

### 3.1. Status

`status` MUST be an `Integer` in `100..599`.

### 3.2. Headers

`headers` MUST be an `Array` of `[name, value]` pairs; each name and value MUST be a `String`. Names MUST NOT contain uppercase ASCII characters. Values are treated as raw bytes.

Duplicate names are permitted. The bridge MUST preserve duplicates and the relative order of pairs sharing a name (e.g. multiple `set-cookie` headers), MAY reorder pairs with different names, and MUST NOT add, merge, or rewrite headers.

### 3.3. Body

`body` MUST be `nil` (empty), a `String` (its bytes are used as-is; encoding is not interpreted), or an `IO::Buffer` (its backing bytes are used without an intermediate String). The buffer MUST remain valid until the bridge finishes serializing the response, and the bridge MUST NOT invalidate request-scoped buffers (section 2) before then.

### 3.4. Ownership

Response memory handed to the host is owned by the bridge, never by Ruby: bridges MUST copy Ruby-provided bytes into memory that survives garbage collection and compaction, and MUST release it according to the host protocol's lifetime rules.

## 4. Concurrency

A bridge MAY be invoked concurrently by its host. A conforming bridge serializes application execution into a single Ruby execution context but MAY multiplex concurrent requests onto Fibers via a `Fiber::Scheduler`, so:

- The application MUST be fiber-reentrant: whenever it sleeps or waits on IO, another request may run before the wait returns. Shared mutable state needs the same care as under any cooperative scheduler.
- The application MUST NOT assume two requests never interleave, and MUST NOT assume they run on different threads (thread-locals are shared; fiber-locals (`Thread#[]`) are per-request under fiber multiplexing).
- Blocking a request without going through a scheduler-aware primitive (e.g. spinning, or C extensions that block the thread) stalls every in-flight request; applications SHOULD avoid it.

The bridge MAY allow the application to supply its own conforming `Fiber::Scheduler`; the application contract itself never depends on which scheduler runs.

## 5. Errors

- Application exception from `call`: 500 response, request buffers still invalidated, host never crashes.
- Malformed response: the bridge MUST NOT crash; it SHOULD respond 500.
- Bridge overload: the bridge MAY reject new requests with a 503 before dispatching them to the application.
