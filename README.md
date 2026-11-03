# openresponses.zig

A generated Open Responses SDK for Zig 0.17.0.
It supports `POST /responses` and `POST /responses/compact`, including SSE streams.
WebSockets are not supported.

## Install

```sh
zig fetch --save git+https://github.com/h0rv/openresponses.zig
```

Add the module in your `build.zig`:

```zig
const sdk = b.dependency("openresponses", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("openresponses", sdk.module("openresponses"));
```

## Create a response

Set `OPENRESPONSES_API_KEY` and `OPENRESPONSES_BASE_URL` for your provider.
The default URL is `https://api.openai.com/v1`.

```zig
const std = @import("std");
const api = @import("openresponses");

pub fn main(init: std.process.Init) !void {
    const key = init.environ_map.get("OPENRESPONSES_API_KEY") orelse return error.MissingApiKey;

    var client = api.Client.init(init.gpa, init.io, key);
    defer client.deinit();

    if (init.environ_map.get("OPENRESPONSES_BASE_URL")) |url| {
        client.withBaseUrl(url);
    }

    var response = try api.createResponse(&client, .{
        .model = "gpt-5.4-mini",
        .input = .{
            .string = "Say hello.",
        },
    });
    defer response.deinit();

    std.debug.print("{s}\n", .{response.value().id});
}
```

See `examples/smoke.zig` for result handling and streaming.
Use `std.json.Value` for mixed streams or a generated struct for one event type.
There is no combined event union. Streams do not require `[DONE]`.

## Test and regenerate

```sh
zig build test
zig build test -Doptimize=ReleaseSafe
zig build generate -Dregenerate=true
```

Tests compile the example without making API requests.
Only regeneration downloads the specification and runs the pinned generator.
`src/api.zig` is entirely generated. Do not edit it by hand.
The Open Responses source and checksum are in `spec.lock.json`.
The specification is Apache 2.0. Its full license is in `THIRD_PARTY_LICENSES`.
