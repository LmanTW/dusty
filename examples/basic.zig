const std = @import("std");
const zio = @import("zio");
const dusty = @import("dusty");

const AppContext = struct {
    counter: usize = 0,
};

fn handleRoot(ctx: *AppContext, req: *const dusty.Request, res: *dusty.Response) void {
    _ = ctx;
    _ = req;
    _ = res;
    std.log.info("Handling root request", .{});
}

fn handleUser(ctx: *AppContext, req: *const dusty.Request, res: *dusty.Response) void {
    _ = ctx;
    _ = res;
    std.log.info("Handling user request: {s}", .{req.url});
}

fn handlePost(ctx: *AppContext, req: *const dusty.Request, res: *dusty.Response) void {
    _ = req;
    _ = res;
    ctx.counter += 1;
    std.log.info("Post created! Counter: {d}", .{ctx.counter});
}

pub fn runServer(allocator: std.mem.Allocator, rt: *zio.Runtime) !void {
    var ctx: AppContext = .{};

    var server = dusty.Server(AppContext).init(allocator, &ctx);
    defer server.deinit();

    // Register routes
    server.router.get("/", handleRoot);
    server.router.get("/users/:id", handleUser);
    server.router.post("/posts", handlePost);

    const addr = try zio.net.IpAddress.parseIp("127.0.0.1", 8080);
    try server.listen(rt, addr);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var rt = try zio.Runtime.init(allocator, .{});
    defer rt.deinit();

    try rt.runUntilComplete(runServer, .{ allocator, rt }, .{});
}
