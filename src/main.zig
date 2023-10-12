const std = @import("std");
const mem = std.mem;
const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;

// head : List -> Atom
// tail : List -> ?List

pub const Atom = union(enum) {
    boolean: Boolean,
    number: Number,
    symbol: Symbol,
    string: String,

    pub const Boolean = bool;
    pub const Number = i64;
    // workaround, otherwise `switch (T)` would not differentiate Atom.Symbol from Atom.String.
    pub const Symbol = std.meta.Tuple(&.{[]const u8});
    pub const String = []const u8;

    pub fn format(self: Atom, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        return switch (self) {
            .boolean => std.fmt.format(writer, "{s}", .{if (self.boolean) "#t" else "#f"}),
            .number => std.fmt.format(writer, "{d}", .{self.number}),
            .string => std.fmt.format(writer, "\"{s}\"", .{self.string}),
            .symbol => std.fmt.format(writer, "{s}", .{self.symbol[0]}),
        };
    }
};

pub const Cons = union(enum) {
    list: *?List,
    atom: Atom,

    pub fn format(self: Cons, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        return switch (self) {
            .atom => std.fmt.format(writer, "{}", .{self.atom}),
            .list => std.fmt.format(writer, "({?})", .{self.list.*}),
        };
    }
};

pub const List = struct {
    head: Cons,
    tail: *?List,

    pub fn format(self: List, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "{}", .{self.head});

        if (self.tail.*) |tail| {
            try std.fmt.format(writer, " {}", .{tail});
        }
    }
};

const Parser = struct {
    arena: ArenaAllocator,
    buffer: []const u8,
    index: usize,

    const log = std.log.scoped(.parser);

    const whitespace: []const u8 = &std.ascii.whitespace;
    const separator: []const u8 = whitespace ++ "()[]";
    pub const Error = error{ParseFail};

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

    pub fn match(self: *Parser, slice: []const u8) bool {
        const start = self.index;

        if (!mem.eql(u8, self.buffer[start .. start + slice.len], slice)) return false;
        self.index += slice.len;

        return true;
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

    // This might not be the right approach, but it looks cool.
    pub fn parse(self: *Parser, comptime T: type) (Parser.Error || Allocator.Error)!T {
        switch (T) {
            Atom => {
                if (try self.recover(Atom.Number)) |number| return Atom{ .number = number };
                if (try self.recover(Atom.Boolean)) |boolean| return Atom{ .boolean = boolean };
                if (try self.recover(Atom.String)) |string| return Atom{ .string = string };
                if (try self.recover(Atom.Symbol)) |symbol| return Atom{ .symbol = symbol };
                return error.ParseFail;
            },
            Atom.Boolean => {
                if (!self.match("#")) return error.ParseFail;

                if (self.match("t")) return true;
                if (self.match("f")) return false;

                return error.ParseFail;
            },
            Atom.Number => {
                const start = try self.gotoNone(whitespace);
                const end = try self.gotoAny(separator);

                return std.fmt.parseInt(i64, self.buffer[start..end], 0) catch error.ParseFail;
            },
            Atom.String => {
                const allocator = self.arena.allocator();

                _ = try self.gotoNone(whitespace);
                if (!self.match("\"")) return error.ParseFail;
                const start = self.index;

                if (self.match("\"")) {
                    return &[_]u8{};
                } else {
                    const end = try self.gotoAny("\""); // does not check the current index, unexpected.
                    if (!self.match("\"")) return error.ParseFail;

                    return allocator.dupe(u8, self.buffer[start..end]);
                }

                return error.ParseFail;
            },
            Atom.Symbol => {
                const allocator = self.arena.allocator();

                const start = try self.gotoNone(whitespace);
                const end = try self.gotoAny(separator);

                if (start < end) return .{try allocator.dupe(u8, self.buffer[start..end])};

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

                if (try self.recover(Atom)) |atom| return Cons{ .atom = atom };

                _ = try self.gotoNone(whitespace);

                var expect: *const [1]u8 = undefined;
                if (self.match("(")) {
                    expect = ")";
                } else if (self.match("[")) {
                    expect = "]";
                } else return error.ParseFail;

                const list = try allocator.create(?List);
                list.* = try self.recover(List);

                _ = try self.gotoNone(whitespace);
                if (!self.match(expect)) return error.ParseFail;

                return Cons{ .list = list };
            },
            else => @compileError("Parser not defined for " ++ @typeName(T)),
        }
    }

    pub fn deinit(self: *Parser) void {
        self.arena.deinit();
    }

    pub fn init(buffer: []const u8, allocator: Allocator) Parser {
        return .{
            .arena = ArenaAllocator.init(allocator),
            .buffer = buffer,
            .index = 0,
        };
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    var arena = ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    const stdin = std.io.getStdIn();
    const input = try stdin.reader().readAllAlloc(arena.allocator(), 100 * 1028);

    var parser = Parser.init(input, gpa.allocator());
    defer parser.deinit();

    const cons = try parser.parse(Cons);
    std.debug.print("{}\n", .{cons});

    std.debug.print("Arena Occupies: {d}\n", .{parser.arena.queryCapacity()});
}
