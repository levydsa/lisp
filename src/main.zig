const std = @import("std");
const mem = std.mem;
const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;

pub const Atom = union(enum) {
    number: Number,
    symbol: Symbol,

    pub const Number = i64;
    pub const Symbol = []const u8;

    pub fn print(self: Atom) !void {
        switch (self) {
            .number => std.debug.print("{d}\n", .{ self.number }),
            .symbol => std.debug.print("{s}\n", .{ self.symbol })
        }
    }
};

pub const Cons = union(enum) {
    list: List,
    atom: Atom,
};

pub const List = ?struct {
    head: *Cons,
    tail: *List,
};

const Env = struct {
    env: std.StringHashMap(Atom),
};

const Parser = struct {
    arena: ArenaAllocator,
    buffer: []const u8,
    index: usize,

    const log = std.log.scoped(.parser);
    const whitespace: []const u8 = &std.ascii.whitespace;
    const separator: []const u8 = whitespace ++ "()";

    const Error = error{ ParseFail } || Allocator.Error;

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

    pub fn parse(self: *Parser, comptime T: type) Error!T {
        self.index = mem.indexOfNonePos(u8, self.buffer, self.index, whitespace) orelse self.buffer.len;
        switch (T) {
            Atom => {

                if (try self.recover(Atom.Number)) |number| {
                    return Atom{ .number = number };
                } else if (try self.recover(Atom.Symbol)) |symbol| {
                    return Atom{ .symbol = symbol };
                } else {
                    return error.ParseFail;
                }
            },
            Atom.Number => {
                // match until separator ("\r\n\t ()")
                const start = self.index;
                const end = mem.indexOfAnyPos(u8, self.buffer, start, separator) orelse self.buffer.len;
                self.index = end;

                return std.fmt.parseInt(i64, self.buffer[start..end], 0) catch error.ParseFail;
            },
            Atom.Symbol => {
                // match until separator ("\r\n\t ()")
                const start = self.index;
                const end = mem.indexOfAnyPos(u8, self.buffer, start, separator) orelse self.buffer.len;
                self.index = end;

                const allocator = self.arena.allocator();

                return if (start < end) allocator.dupe(u8, self.buffer[start..end]) else error.ParseFail;
            },
            List => {
                const allocator = self.arena.allocator();

                if (try self.recover(Cons)) |head| {
                    const tail = try allocator.create(List);
                    tail.* = try self.parse(List);

                    return List{
                        .head = head,
                        .tail = tail,
                    };
                } else {
                    return null;
                }

                unreachable;
            },
            Cons => {
                // atom or (list)
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
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    const s = "   120   uuu  ";

    var parser = Parser.init(s, gpa.allocator());
    defer parser.deinit();

    try (try parser.parse(Atom)).print();
    try (try parser.parse(Atom)).print();
}
