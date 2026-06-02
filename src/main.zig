const std = @import("std");
const Server = @import("http/http_server.zig").Server;
const Request = @import("http/request.zig");
const Response = @import("http/response.zig");
const Method = Request.Method;

fn add_and_increment(a: u8, b: u8) u8 {
    const sum = a + b;
    const incremented = sum + 1;
    return incremented;
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const result = add_and_increment(10, 5);
    try stdout.print("The result is {d}\n", .{result});
    try stdout.flush();

    const io = init.io;
    const server = try Server.init(io);
    var listening = try server.listen();
    const connection = try listening.accept(io);
    defer connection.close(io);

    var request_buffer: [1024]u8 = undefined;
    @memset(request_buffer[0..], 0);
    try Request.read_request(io, connection, request_buffer[0..]);

    std.debug.print("{s}\n", .{request_buffer});

    const request = Request.parse_request(request_buffer[0..]);
    std.debug.print("{any}\n", .{request});

    if (request.method == Method.GET) {
        if (std.mem.eql(u8, request.uri, "/")) {
            try Response.send_200(connection, io);
        } else {
            try Response.send_404(connection, io);
        }
    }
}
