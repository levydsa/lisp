const std = @import("std");
const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;

pub const Atom = union(enum) {
    number: Number,
    symbol: Symbol,

    pub const Number = i64;
    pub const Symbol = []const u8;
};

pub const Expr = struct {
    head: union(enum) {
        expr: *Expr,
        atom: Atom,
    },
    tail: *Expr,
};

const Env = struct {
    env: std.StringHashMap(Atom),
};

const Parser = struct {
    arena: ArenaAllocator,
    buffer: []const u8,
    index: usize,

    const log = std.log.scoped(.parser);
    const separator: []const u8 = &std.ascii.whitespace ++ [_]u8{ '(', ')' };

    const Error = error{
        ParseFail,
        EndOfBuffer,
    } || Allocator.Error;

    pub fn match(self: *Parser, comptime pattern: anytype) !void {
        if (@TypeOf(pattern) == []const u8) {
            if (self.buffer.len < self.index) {
                return Error.EndOfBuffer;
            }

            const token = self.buffer[self.index..];
            if (std.mem.eql(u8, token[0..pattern.len], pattern)) {
                self.index += pattern.len;
                return;
            }

            return Error.ParseFail;
        }
    }

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
        switch (T) {
            Atom => {
                self.index = std.mem.indexOfNonePos(u8, self.buffer, self.index, &std.ascii.whitespace) orelse self.buffer.len;

                if (try self.recover(Atom.Number)) |number| {
                    return Atom{ .number = number };
                } else if (try self.recover(Atom.Symbol)) |symbol| {
                    return Atom{ .symbol = symbol };
                } else {
                    return error.ParseFail;
                }
            },
            Atom.Number => {
                const start = self.index;
                const end = std.mem.indexOfAnyPos(u8, self.buffer, start, separator) orelse self.buffer.len;
                self.index = end;

                return std.fmt.parseInt(i64, self.buffer[start..end], 0) catch error.ParseFail;
            },
            Atom.Symbol => {
                const start = self.index;
                const end = std.mem.indexOfAnyPos(u8, self.buffer, start, separator) orelse self.buffer.len;
                self.index = end;

                if (start < end) {
                    return self.arena.allocator().dupe(u8, self.buffer[start..end]);
                } else {
                    return error.ParseFail;
                }
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

    std.debug.print("{} {d}\n", .{ try parser.parse(Atom), parser.index });
    std.debug.print("{} {d}\n", .{ try parser.parse(Atom), parser.index });
}
