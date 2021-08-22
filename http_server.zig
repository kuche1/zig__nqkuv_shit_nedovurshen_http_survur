
const std = @import("std");
const echo = std.debug.print;
const net = std.net;
const stdin = std.io.getStdIn().reader();

const Settings = @import("./settings.zig").Settings;

const PORT = 7564; // 0 for random
const ADDR = "0.0.0.0"; // 0.0.0.0 for any

const ACCEPTANCE_QUEUE = 8;

const MAX_THREADS_LIMIT = 64;
const BE_GENTLE_TO_THREADS = false; // this is not fully implemented, will never be

const HEADER_MAXLEN = 500;
const HEADER_END = "\r\n\r\n";

/////

//const fs = std.fs; // useless?
//const os = std.os; // useless?
//pub const io_mode = .evented; // wtf kvo pravi tva, zaradi nego ne mojeh da puskam thread-ove // tva e za async

pub fn main() !void {
    //var allocator = std.heap.GeneralPurposeAllocator(.{}){};
    //const aloc = &allocator.allocator;

    var settings = Settings{};

    var server = net.StreamServer.init(.{.kernel_backlog=ACCEPTANCE_QUEUE, .reuse_address=true});
    defer server.deinit();
    defer server.close(); // deinit go vika anyways

    const addr = net.Address.parseIp(ADDR, PORT) catch |e| {
        echo("could not parse address\n",.{});
        return e;
    };
    
    server.listen(addr) catch |e| {
       echo("could not listed to address\n",.{});
       return e;
    };

    echo("listening at {}\n", .{server.listen_address});

    const accept_thr = try std.Thread.spawn(accept_new_connections, .{.server=&server, .settings=&settings});
    defer _ = BE_GENTLE_TO_THREADS and accept_thr.wait();

    var inp_buf: [1]u8 = undefined;
    const inp = stdin.readUntilDelimiterOrEof(inp_buf[0..], '\n');

    echo("end\n", .{});

}

const Ctx_accept_new_connections = struct{
    server: *std.net.StreamServer,
    settings: *Settings,
};

fn accept_new_connections(ctx: Ctx_accept_new_connections) !void {
    var server = ctx.server;
    var settings = ctx.settings;

    var thr_done: [MAX_THREADS_LIMIT]bool = .{true} ** MAX_THREADS_LIMIT;
    var thr_hdl: [MAX_THREADS_LIMIT]?*std.Thread = .{null} ** MAX_THREADS_LIMIT;
    var thr_idx: u8 = 0;

    defer {
        for(thr_hdl)|handle|{
            if(handle)|hdl|{
                _ = BE_GENTLE_TO_THREADS and hdl.wait();
            }
        }
    }

    while (true) {

        while (!thr_done[thr_idx]) {
            thr_idx += 1;
            thr_idx %= settings.max_threads;
        }

        if (thr_hdl[thr_idx])|handle|{
            handle.wait();
        }

        const conn = try server.accept();

        thr_done[thr_idx] = false;
        const thr = try std.Thread.spawn(handle_a_client, .{.conn=conn, .done=&thr_done[thr_idx]});
        thr_hdl[thr_idx] = thr;

     }
}

const Ctx_handle_a_client = struct {
    conn: std.net.StreamServer.Connection,
    done: *bool,
};

fn handle_a_client(ctx: Ctx_handle_a_client) !void {
    const conn = ctx.conn;
    var done = ctx.done;

    defer done.* = true;
    defer conn.stream.close();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const aloc = &arena.allocator;

    const client = try aloc.create(Client);

    client.* = Client{
        .conn = conn,
    };
    
    try client.handle(aloc);

}

const Client = struct {
    conn: net.StreamServer.Connection,

    fn handle(self: *Client, aloc: *std.mem.Allocator) !void {

        var buf: [HEADER_MAXLEN]u8 = undefined;
        const red = self.conn.stream.read(&buf) catch |e| {
            echo("ne moga da 4eta ve4e\n", .{});
            return e;
        };

        const raw_msg = buf[0..red];

        if(!std.mem.endsWith(u8, raw_msg, HEADER_END)){
            echo("bad header\n", .{});
            return;
        }

        const msg = raw_msg[0 .. raw_msg.len - HEADER_END.len];

        //echo("msg: {s}\n", .{msg});

        _ = self.conn.stream.write(msg) catch |e| echo("unable to send: {}\n", .{e});

    }
};

fn file_read_example()void{
        var f = std.fs.openFileAbsolute("./socket_stuff.zig", .{.read=true}) catch |e| {
            echo("sori, faila go nqma\n", .{});
            return e;
        };
        defer f.close();

        var fcont: [5000]u8 = undefined;
        var read = f.read(fcont[0..]) catch |e| {
            echo("ne mojah da pro4eta\n", .{});
            return e;
        };

        _ = self.conn.stream.write(fcont[0..]) catch |e| echo("unable to send: {}\n", .{e});
}

