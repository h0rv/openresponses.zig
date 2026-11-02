const std = @import("std");
const openresponses = @import("openresponses");

// `zig build test` compiles this example but does not run it.
// Set OPENRESPONSES_API_KEY and OPENRESPONSES_BASE_URL before running it.
pub fn main(init: std.process.Init) !void {
    const key = init.environ_map.get("OPENRESPONSES_API_KEY") orelse return error.MissingApiKey;
    const base_url = init.environ_map.get("OPENRESPONSES_BASE_URL") orelse return error.MissingBaseUrl;
    var client = openresponses.Client.init(init.gpa, init.io, key);
    defer client.deinit();
    client.withBaseUrl(base_url);

    const request: openresponses.CreateResponseBody = .{
        .model = "gpt-5.4-mini",
        .input = .{ .string = "Say hello." },
    };
    var response = try openresponses.createResponse(&client, request);
    defer response.deinit();

    var result = try openresponses.createResponseResult(&client, request);
    defer result.deinit();

    var compacted = try openresponses.compactResponse(&client, .{
        .model = "gpt-5.4-mini",
        .previous_response_id = response.value().id,
    });
    defer compacted.deinit();

    var compact_result = try openresponses.compactResponseResult(&client, .{
        .model = "gpt-5.4-mini",
        .previous_response_id = response.value().id,
    });
    defer compact_result.deinit();

    // There is no generated union for the inline SSE oneOf in this spec.
    // std.json.Value accepts all event variants. Specific event structs also exist.
    var events = Events{};
    try openresponses.createResponseStreamingEvents(std.json.Value, &client, request, &events, null);
}

const Events = struct {
    pub fn event(_: *@This(), _: *std.json.Value) !void {}
};
