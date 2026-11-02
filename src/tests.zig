const std = @import("std");
const api = @import("openresponses");
const allocator = std.testing.allocator;

test "all generated endpoint declarations compile" {
    @setEvalBranchQuota(100_000);
    std.testing.refAllDecls(api);
}

test "results retain HTTP errors and failed decoding bodies" {
    const gpa = std.testing.allocator;
    var failure = try api.parseRawResponse(std.json.Value, .{
        .allocator = gpa,
        .status = .too_many_requests,
        .body = try gpa.dupe(u8, "rate limited"),
    });
    defer failure.deinit();
    try std.testing.expect(failure == .api_error);
    try std.testing.expectEqualStrings("rate limited", failure.api_error.body);
    try std.testing.expectEqual(std.http.Status.too_many_requests, failure.api_error.status);

    var malformed = try api.parseRawResponse(std.json.Value, .{
        .allocator = gpa,
        .status = .ok,
        .body = try gpa.dupe(u8, "not json"),
    });
    defer malformed.deinit();
    try std.testing.expect(malformed == .parse_error);
    try std.testing.expectEqualStrings("not json", malformed.parse_error.raw.body);

    var success = try api.parseRawResponse(std.json.Value, .{
        .allocator = gpa,
        .status = .ok,
        .body = try gpa.dupe(u8, "{\"id\":\"response\"}"),
    });
    defer success.deinit();
    try std.testing.expect(success == .ok);
    try std.testing.expectEqualStrings("response", success.ok.value().object.get("id").?.string);
}

test "create requests omit absent fields on the wire" {
    const request: api.CreateResponseBody = .{
        .model = "future-model",
        .input = .{ .string = "Hello" },
    };
    const json = try std.json.Stringify.valueAlloc(allocator, request, .{ .emit_null_optional_fields = false });
    defer allocator.free(json);
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("future-model", parsed.value.object.get("model").?.string);
    try std.testing.expectEqualStrings("Hello", parsed.value.object.get("input").?.string);
    try std.testing.expect(parsed.value.object.get("temperature") == null);
    try std.testing.expect(parsed.value.object.get("stream") == null);
}

test "compact requests omit absent fields on the wire" {
    const request: api.CompactResponseMethodPublicBody = .{ .model = "future-model" };
    const json = try std.json.Stringify.valueAlloc(allocator, request, .{ .emit_null_optional_fields = false });
    defer allocator.free(json);
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(usize, 1), parsed.value.object.count());
}

test "response tools preserve function parameter schemas" {
    const json =
        \\{"type":"function","name":"weather","description":null,"strict":true,
        \\ "parameters":{"type":"object","properties":{"city":{"type":"string"}},"required":["city"],"additionalProperties":false}}
    ;
    var tool = try std.json.parseFromSlice(api.Tool, allocator, json, .{});
    defer tool.deinit();
    try std.testing.expect(tool.value == .function);
    try std.testing.expectEqualStrings("weather", tool.value.function.name);
    const encoded = try std.json.Stringify.valueAlloc(allocator, tool.value, .{});
    defer allocator.free(encoded);
    var roundtrip = try std.json.parseFromSlice(std.json.Value, allocator, encoded, .{});
    defer roundtrip.deinit();
    const schema = roundtrip.value.object.get("parameters").?.object;
    try std.testing.expectEqualStrings("object", schema.get("type").?.string);
    try std.testing.expectEqualStrings("string", schema.get("properties").?.object.get("city").?.object.get("type").?.string);
    try std.testing.expect(!schema.get("additionalProperties").?.bool);
}

test "unknown provider tools remain available as raw JSON" {
    var tool = try std.json.parseFromSlice(api.ResponsesToolParam, allocator, "{\"type\":\"provider_tool\",\"enabled\":true}", .{});
    defer tool.deinit();
    try std.testing.expect(tool.value == .raw);
    try std.testing.expect(tool.value.raw.object.get("enabled").?.bool);
}

test "raw request helpers can serialize provider extensions" {
    // postJsonRaw accepts any serializable request, including provider fields.
    const request = .{ .model = "future-model", .provider_option = true };
    const json = try std.json.Stringify.valueAlloc(allocator, request, .{ .emit_null_optional_fields = false });
    defer allocator.free(json);
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value.object.get("extra_body") == null);
    try std.testing.expect(parsed.value.object.get("provider_option").?.bool);
}

test "typed SSE deltas parse without a DONE marker" {
    const Collector = struct {
        count: usize = 0,
        pub fn event(self: *@This(), value: *api.ResponseOutputTextDeltaStreamingEvent) !void {
            try std.testing.expectEqualStrings("response.output_text.delta", value.type);
            try std.testing.expectEqualStrings("Hello", value.delta);
            self.count += 1;
        }
    };
    var collector = Collector{};
    try api.parseSseBytesTyped(api.ResponseOutputTextDeltaStreamingEvent, allocator,
        \\event: response.output_text.delta
        \\data: {"type":"response.output_text.delta","sequence_number":1,"item_id":"msg_1","output_index":0,"content_index":0,"delta":"Hello","logprobs":[]}
        \\
        \\
    , &collector, null);
    try std.testing.expectEqual(@as(usize, 1), collector.count);
}

const response_json =
    \\{"id":"resp_1","object":"response","created_at":1,"completed_at":null,"status":"completed",
    \\ "instructions":null,"tools":[{"type":"function","name":"weather","description":null,"strict":true,"parameters":{"type":"object"}}],
    \\ "store":false,"model":"future-model","incomplete_details":null,"error":null,"parallel_tool_calls":true,
    \\ "safety_identifier":null,"text":{"format":{"type":"text"}},"metadata":{},"previous_response_id":null,
    \\ "top_logprobs":0,"reasoning":null,"truncation":"disabled","max_tool_calls":null,"temperature":1,
    \\ "max_output_tokens":null,"usage":null,"background":false,"frequency_penalty":0,"presence_penalty":0,
    \\ "output":[],"tool_choice":"auto","top_p":1,"service_tier":"default","prompt_cache_key":null}
;

test "response resources parse function tools and open model names" {
    var response = try std.json.parseFromSlice(api.ResponseResource, allocator, response_json, .{});
    defer response.deinit();
    try std.testing.expectEqualStrings("future-model", response.value.model);
    try std.testing.expect(response.value.tools[0] == .function);
}

test "all terminal SSE event structs parse without a DONE marker" {
    inline for (.{
        .{ api.ResponseCompletedStreamingEvent, "response.completed" },
        .{ api.ResponseFailedStreamingEvent, "response.failed" },
        .{ api.ResponseIncompleteStreamingEvent, "response.incomplete" },
    }) |case| {
        const Event = case[0];
        const name = case[1];
        const Collector = struct {
            count: usize = 0,
            pub fn event(self: *@This(), value: *Event) !void {
                try std.testing.expectEqualStrings(name, value.type);
                try std.testing.expectEqualStrings("resp_1", value.response.id);
                self.count += 1;
            }
        };
        const envelope = try allocator.print("{{\"type\":\"{s}\",\"sequence_number\":2,\"response\":{s}}}", .{ name, response_json });
        defer allocator.free(envelope);
        // SSE data is one line. The embedded response fixture has newlines.
        var value = try std.json.parseFromSlice(std.json.Value, allocator, envelope, .{});
        defer value.deinit();
        const compact = try std.json.Stringify.valueAlloc(allocator, value.value, .{});
        defer allocator.free(compact);
        const bytes = try allocator.print("event: {s}\ndata: {s}\n\n", .{ name, compact });
        defer allocator.free(bytes);
        var collector = Collector{};
        try api.parseSseBytesTyped(Event, allocator, bytes, &collector, null);
        try std.testing.expectEqual(@as(usize, 1), collector.count);
    }
}
