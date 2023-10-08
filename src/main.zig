const std = @import("std");
const mem = std.mem;
const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;

// head : List -> Atom
// tail : List -> ?List

pub const Atom = union(enum) {
    boolean: bool,
    number: i64,
    symbol: []const u8,
};

pub const Cons = union(enum) {
    list: *?List,
    atom: Atom,

    pub fn print(self: *const Cons, space: u8) void {
        switch (self.*) {
            .list => |list| if (list.*) |some| {
                some.print(space);
            } else {
                std.debug.print("{s: >[1]}null\n", .{ "", space * 2 });
            },
            .atom => |atom| std.debug.print("{s: >[2]}{}\n", .{ "", atom, space * 2 }),
        }
    }
};

pub const List = struct {
    head: Cons,
    tail: *?List,

    pub fn print(self: *const List, space: u8) void {
        self.head.print(space);
        if (self.tail.*) |tail| {
            tail.print(space + 1);
        } else {
            std.debug.print("{s: >[1]}null\n", .{ "", space * 2 });
        }
    }
};

const Parser = struct {
    arena: ArenaAllocator,
    buffer: []const u8,
    index: usize,

    const log = std.log.scoped(.parser);
    const whitespace: []const u8 = &std.ascii.whitespace;
    const separator: []const u8 = whitespace ++ "()";

    const Error = error{ParseFail} || Allocator.Error;

    pub fn recover(self: *Parser, comptime T: type) !?T {
        const start = self.index;
        return self.parse(T) catch |err| switch (err) {
            error.ParseFail => {
                self.index = start;
                return null;
            },
            else => return err,
        };
    }

    pub fn match(self: *Parser, slice: []const u8) !void {
        const start = try self.gotoNone(whitespace);
        if (!mem.eql(u8, self.buffer[start .. start + slice.len], slice)) {
            return error.ParseFail;
        }
        self.index += slice.len;
    }

    pub fn gotoAny(self: *Parser, values: []const u8) Error!usize {
        if (mem.indexOfAnyPos(u8, self.buffer, self.index, values)) |index| {
            self.index = index;
            return self.index;
        }
        return error.ParseFail;
    }

    pub fn gotoNone(self: *Parser, values: []const u8) Error!usize {
        if (mem.indexOfNonePos(u8, self.buffer, self.index, values)) |index| {
            self.index = index;
            return self.index;
        }
        return error.ParseFail;
    }

    pub fn parse(self: *Parser, comptime T: type) Error!T {
        switch (T) {
            Atom => {
                if (try self.recover(i64)) |number| {
                    return Atom{ .number = number };
                }

                if (try self.recover([]const u8)) |symbol| {
                    return Atom{ .symbol = symbol };
                }

                return error.ParseFail;
            },
            i64 => {
                const start = try self.gotoNone(whitespace);
                const end = try self.gotoAny(separator);

                return std.fmt.parseInt(i64, self.buffer[start..end], 0) catch error.ParseFail;
            },
            []const u8 => {
                const allocator = self.arena.allocator();

                const start = try self.gotoNone(whitespace);
                const end = try self.gotoAny(separator);

                if (start < end) {
                    const sym = try allocator.dupe(u8, self.buffer[start..end]);
                    return sym;
                }

                return error.ParseFail;
            },
            List => {
                const allocator = self.arena.allocator();

                if (try self.recover(Cons)) |head| {
                    const tail = try allocator.create(?List);
                    tail.* = try self.recover(List);

                    return List{
                        .head = head,
                        .tail = tail,
                    };
                }

                return error.ParseFail;
            },
            Cons => {
                const allocator = self.arena.allocator();

                if (try self.recover(Atom)) |atom| {
                    return Cons{ .atom = atom };
                }

                try self.match("(");
                const list = try allocator.create(?List);
                list.* = try self.recover(List);
                try self.match(")");

                return Cons{ .list = list };
            },
            else => @compileError("Parser not defined for " ++ @typeName(T)),
        }
    }

    pub fn deinit(self: *Parser) void {
        self.arena.deinit();
    }

    pub fn init(buffer: []const u8, allocator: Allocator) Parser {
        const arena = ArenaAllocator.init(allocator);

        return Parser{
            .arena = arena,
            .buffer = buffer,
            .index = 0,
        };
    }
};

pub fn main() !void {
    std.debug.print("{d}\n", .{@sizeOf(i64)});
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    const s = "(255 (foo) (bar baz 123 412) λ α)";

    var parser = Parser.init(s, gpa.allocator());
    defer parser.deinit();

    const cons = try parser.parse(Cons);
    cons.print(0);
}
