const std = @import("std");
const Request = @import("request.zig").Request;
const Response = @import("response.zig").Response;
const Method = @import("http.zig").Method;

pub fn Router(comptime Ctx: type) type {
    return struct {
        const Self = @This();

        pub const Handler = *const fn (*Ctx, *const Request, *Response) void;

        const Route = struct {
            method: Method,
            path: []const u8,
            handler: Handler,
        };

        allocator: std.mem.Allocator,
        routes: std.ArrayList(Route),

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .routes = .{},
            };
        }

        pub fn deinit(self: *Self) void {
            for (self.routes.items) |route| {
                self.allocator.free(route.path);
            }
            self.routes.deinit(self.allocator);
        }

        fn addRoute(self: *Self, method: Method, path: []const u8, handler: anytype) void {
            const owned_path = self.allocator.dupe(u8, path) catch @panic("OOM");
            self.routes.append(self.allocator, .{
                .method = method,
                .path = owned_path,
                .handler = handler,
            }) catch @panic("OOM");
        }

        pub fn get(self: *Self, path: []const u8, handler: anytype) void {
            self.addRoute(.get, path, handler);
        }

        pub fn head(self: *Self, path: []const u8, handler: anytype) void {
            self.addRoute(.head, path, handler);
        }

        pub fn post(self: *Self, path: []const u8, handler: anytype) void {
            self.addRoute(.post, path, handler);
        }

        pub fn put(self: *Self, path: []const u8, handler: anytype) void {
            self.addRoute(.put, path, handler);
        }

        pub fn delete(self: *Self, path: []const u8, handler: anytype) void {
            self.addRoute(.delete, path, handler);
        }

        fn matchPath(pattern: []const u8, url: []const u8) bool {
            var pattern_iter = std.mem.splitScalar(u8, pattern, '/');
            var url_iter = std.mem.splitScalar(u8, url, '/');

            while (pattern_iter.next()) |pattern_seg| {
                const url_seg = url_iter.next() orelse return false;

                // Skip empty segments (from leading or trailing slashes)
                if (pattern_seg.len == 0 and url_seg.len == 0) continue;
                if (pattern_seg.len == 0) return false;
                if (url_seg.len == 0) return false;

                // Path parameter - matches any segment
                if (pattern_seg[0] == ':') continue;

                // Static segment - must match exactly
                if (!std.mem.eql(u8, pattern_seg, url_seg)) return false;
            }

            // Both iterators should be exhausted
            return url_iter.next() == null;
        }

        pub fn findHandler(self: *const Self, req: *Request) !?Handler {
            for (self.routes.items) |route| {
                if (route.method == req.method and matchPath(route.path, req.url)) {
                    // Extract parameters using request arena
                    var pattern_iter = std.mem.splitScalar(u8, route.path, '/');
                    var url_iter = std.mem.splitScalar(u8, req.url, '/');

                    while (pattern_iter.next()) |pattern_seg| {
                        const url_seg = url_iter.next() orelse break;

                        // Skip empty segments
                        if (pattern_seg.len == 0) continue;

                        // Extract parameter
                        if (pattern_seg[0] == ':') {
                            const param_name = pattern_seg[1..]; // Skip the ':'
                            try req.params.put(req.arena, param_name, url_seg);
                        }
                    }

                    return route.handler;
                }
            }
            return null;
        }
    };
}

// Tests
const TestRouter = Router(TestContext);

const TestContext = struct {
    called: bool = false,
};

fn testHandler(ctx: *TestContext, req: *const Request, res: *Response) void {
    _ = req;
    _ = res;
    ctx.called = true;
}

fn testHandler2(ctx: *TestContext, req: *const Request, res: *Response) void {
    _ = req;
    _ = res;
    _ = ctx;
}

test "matchPath: exact match" {
    try std.testing.expect(TestRouter.matchPath("/users", "/users"));
    try std.testing.expect(TestRouter.matchPath("/", "/"));
    try std.testing.expect(TestRouter.matchPath("/api/v1/users", "/api/v1/users"));
}

test "matchPath: no match" {
    try std.testing.expect(!TestRouter.matchPath("/users", "/posts"));
    try std.testing.expect(!TestRouter.matchPath("/users", "/users/123"));
    try std.testing.expect(!TestRouter.matchPath("/users/123", "/users"));
    try std.testing.expect(!TestRouter.matchPath("/api/v1", "/api/v2"));
}

test "matchPath: path parameters" {
    try std.testing.expect(TestRouter.matchPath("/users/:id", "/users/123"));
    try std.testing.expect(TestRouter.matchPath("/users/:id", "/users/abc"));
    try std.testing.expect(TestRouter.matchPath("/users/:id/posts", "/users/123/posts"));
    try std.testing.expect(TestRouter.matchPath("/users/:userId/posts/:postId", "/users/123/posts/456"));
}

test "matchPath: path parameters no match" {
    try std.testing.expect(!TestRouter.matchPath("/users/:id", "/users"));
    try std.testing.expect(!TestRouter.matchPath("/users/:id", "/users/123/extra"));
    try std.testing.expect(!TestRouter.matchPath("/users/:id/posts", "/users/123/comments"));
}

test "matchPath: trailing slashes" {
    try std.testing.expect(TestRouter.matchPath("/users/", "/users/"));
    try std.testing.expect(!TestRouter.matchPath("/users", "/users/"));
    try std.testing.expect(!TestRouter.matchPath("/users/", "/users"));
}

test "Router: register and find GET route" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var router = TestRouter.init(std.testing.allocator);
    defer router.deinit();

    router.get("/users", testHandler);

    var req = Request{
        .method = .get,
        .url = "/users",
        .arena = arena.allocator(),
    };

    const handler = try router.findHandler(&req);
    try std.testing.expect(handler != null);
    try std.testing.expect(handler.? == testHandler);
}

test "Router: register and find POST route" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var router = TestRouter.init(std.testing.allocator);
    defer router.deinit();

    router.post("/posts", testHandler);

    var req = Request{
        .method = .post,
        .url = "/posts",
        .arena = arena.allocator(),
    };

    const handler = try router.findHandler(&req);
    try std.testing.expect(handler != null);
    try std.testing.expect(handler.? == testHandler);
}

test "Router: method mismatch returns null" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var router = TestRouter.init(std.testing.allocator);
    defer router.deinit();

    router.get("/users", testHandler);

    var req = Request{
        .method = .post,
        .url = "/users",
        .arena = arena.allocator(),
    };

    const handler = try router.findHandler(&req);
    try std.testing.expect(handler == null);
}

test "Router: path mismatch returns null" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var router = TestRouter.init(std.testing.allocator);
    defer router.deinit();

    router.get("/users", testHandler);

    var req = Request{
        .method = .get,
        .url = "/posts",
        .arena = arena.allocator(),
    };

    const handler = try router.findHandler(&req);
    try std.testing.expect(handler == null);
}

test "Router: parameterized routes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var router = TestRouter.init(std.testing.allocator);
    defer router.deinit();

    router.get("/users/:id", testHandler);

    var req = Request{
        .method = .get,
        .url = "/users/123",
        .arena = arena.allocator(),
    };

    const handler = try router.findHandler(&req);
    try std.testing.expect(handler != null);
    try std.testing.expect(handler.? == testHandler);
}

test "Router: multiple routes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var router = TestRouter.init(std.testing.allocator);
    defer router.deinit();

    router.get("/users", testHandler);
    router.post("/users", testHandler2);
    router.get("/posts", testHandler2);

    // Find first route
    var req1 = Request{
        .method = .get,
        .url = "/users",
        .arena = arena.allocator(),
    };
    const handler1 = try router.findHandler(&req1);
    try std.testing.expect(handler1 != null);
    try std.testing.expect(handler1.? == testHandler);

    // Find second route
    var req2 = Request{
        .method = .post,
        .url = "/users",
        .arena = arena.allocator(),
    };
    const handler2 = try router.findHandler(&req2);
    try std.testing.expect(handler2 != null);
    try std.testing.expect(handler2.? == testHandler2);

    // Find third route
    var req3 = Request{
        .method = .get,
        .url = "/posts",
        .arena = arena.allocator(),
    };
    const handler3 = try router.findHandler(&req3);
    try std.testing.expect(handler3 != null);
    try std.testing.expect(handler3.? == testHandler2);
}

test "Router: all HTTP methods" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var router = TestRouter.init(std.testing.allocator);
    defer router.deinit();

    router.get("/resource", testHandler);
    router.post("/resource", testHandler);
    router.put("/resource", testHandler);
    router.delete("/resource", testHandler);
    router.head("/resource", testHandler);

    const methods = [_]Method{ .get, .post, .put, .delete, .head };
    for (methods) |method| {
        var req = Request{
            .method = method,
            .url = "/resource",
            .arena = arena.allocator(),
        };
        const handler = try router.findHandler(&req);
        try std.testing.expect(handler != null);
    }
}

test "Router: extract single parameter" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var router = TestRouter.init(std.testing.allocator);
    defer router.deinit();

    router.get("/users/:id", testHandler);

    var req = Request{
        .method = .get,
        .url = "/users/123",
        .arena = arena.allocator(),
    };

    const handler = try router.findHandler(&req);
    try std.testing.expect(handler != null);

    const id = req.params.get("id");
    try std.testing.expect(id != null);
    try std.testing.expectEqualStrings("123", id.?);
}

test "Router: extract multiple parameters" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var router = TestRouter.init(std.testing.allocator);
    defer router.deinit();

    router.get("/users/:userId/posts/:postId", testHandler);

    var req = Request{
        .method = .get,
        .url = "/users/456/posts/789",
        .arena = arena.allocator(),
    };

    const handler = try router.findHandler(&req);
    try std.testing.expect(handler != null);

    const userId = req.params.get("userId");
    try std.testing.expect(userId != null);
    try std.testing.expectEqualStrings("456", userId.?);

    const postId = req.params.get("postId");
    try std.testing.expect(postId != null);
    try std.testing.expectEqualStrings("789", postId.?);
}

test "Router: mixed static and parameter segments" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var router = TestRouter.init(std.testing.allocator);
    defer router.deinit();

    router.get("/api/v1/users/:id/profile", testHandler);

    var req = Request{
        .method = .get,
        .url = "/api/v1/users/abc123/profile",
        .arena = arena.allocator(),
    };

    const handler = try router.findHandler(&req);
    try std.testing.expect(handler != null);

    const id = req.params.get("id");
    try std.testing.expect(id != null);
    try std.testing.expectEqualStrings("abc123", id.?);
}
