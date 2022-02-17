const std = @import("std");

pub fn Iter(comptime T: type) type {
    return struct {
        pub const VTable = struct {
            next: fn (*anyopaque) ?T,
        };

        const Self = @This();

        ptr: *anyopaque,
        vtable: *const VTable,

        pub fn init(pointer: anytype) Self {
            const Ptr = @TypeOf(pointer);
            const ptr_info = @typeInfo(Ptr);

            std.debug.assert(ptr_info == .Pointer);
            std.debug.assert(ptr_info.Pointer.size == .One);

            const alignment = ptr_info.Pointer.alignment;

            const gen = struct {
                fn nextImpl(ptr: *anyopaque) ?T {
                    const self = @ptrCast(Ptr, @alignCast(alignment, ptr));
                    return @call(.{ .modifier = .always_inline }, ptr_info.Pointer.child.next, .{self});
                }

                const vtable = VTable{
                    .next = nextImpl,
                };
            };

            return .{
                .ptr = pointer,
                .vtable = &gen.vtable,
            };
        }

        pub inline fn next(self: Self) ?T {
            return self.vtable.next(self.ptr);
        }

        pub fn reduce(
            self: Self,
            start: anytype,
            op: fn (@TypeOf(start), T) @TypeOf(start),
        ) @TypeOf(start) {
            var result = start;
            while (self.next()) |item| result = op(result, item);
            return result;
        }

        pub fn reduceOp(self: Self, start: T, op: std.builtin.ReduceOp) T {
            var result = start;
            while (self.next()) |item| result = switch (op) {
                .And => result & item,
                .Or => result | item,
                .Xor => result ^ item,
                .Min => std.math.min(result, item),
                .Max => std.math.max(result, item),
                .Add => result + item,
                .Mul => result * item,
            };
            return result;
        }

        pub fn forEach(self: Self, op: fn (T) void) void {
            while (self.next()) |item| op(item);
        }

        pub fn forEachError(
            self: Self,
            op: fn (T) anyerror!void,
        ) !void {
            while (self.next()) |item| try op(item);
        }
    };
}

test "reduce" {
    var range = Range(u32).init(0, 10);
    const iter = range.iter();

    const op = struct {
        fn op(acc: u32, item: u32) u32 {
            return acc + item;
        }
    }.op;

    try std.testing.expectEqual(@as(u32, 45), iter.reduce(@as(u32, 0), op));
}

test "reduceOp" {
    {
        var range = Range(u32).init(0, 10);
        const iter = range.iter();
        try std.testing.expectEqual(@as(u32, 0), iter.reduceOp(@as(u32, 0), .And));
    }
    {
        var range = Range(u32).init(0, 10);
        const iter = range.iter();
        try std.testing.expectEqual(@as(u32, 15), iter.reduceOp(@as(u32, 0), .Or));
    }
    {
        var range = Range(u32).init(0, 10);
        const iter = range.iter();
        try std.testing.expectEqual(@as(u32, 1), iter.reduceOp(@as(u32, 0), .Xor));
    }
    {
        var range = Range(u32).init(0, 10);
        const iter = range.iter();
        try std.testing.expectEqual(@as(u32, 0), iter.reduceOp(@as(u32, 0), .Min));
    }
    {
        var range = Range(u32).init(0, 10);
        const iter = range.iter();
        try std.testing.expectEqual(@as(u32, 9), iter.reduceOp(@as(u32, 0), .Max));
    }
    {
        var range = Range(u32).init(0, 10);
        const iter = range.iter();
        try std.testing.expectEqual(@as(u32, 45), iter.reduceOp(@as(u32, 0), .Add));
    }
    {
        var range = Range(u32).init(0, 10);
        const iter = range.iter();
        try std.testing.expectEqual(@as(u32, 0), iter.reduceOp(@as(u32, 0), .Mul));
    }
}

var foo: u32 = undefined;
fn forEachOp(x: u32) void {
    foo += x;
}

test "forEach" {
    foo = 0;
    var range = Range(u32).init(0, 10);
    const iter = range.iter();
    iter.forEach(forEachOp);
    try std.testing.expectEqual(@as(u32, 45), foo);
}

fn forEachErrorOp(x: u32) !void {
    foo += x;
    if (foo > 20) return error.ForEachError;
}

test "forEachError no error" {
    foo = 0;
    var range = Range(u32).init(0, 5);
    const iter = range.iter();
    try iter.forEachError(forEachErrorOp);
    try std.testing.expectEqual(@as(u32, 10), foo);
}

test "forEachError with error" {
    foo = 0;
    var range = Range(u32).init(0, 10);
    const iter = range.iter();
    try std.testing.expectError(error.ForEachError, iter.forEachError(forEachErrorOp));
}

pub fn Counter(comptime T: type) type {
    return struct {
        const Self = @This();

        current: T,

        pub fn init(start: T) Self {
            return .{ .current = start };
        }

        pub fn next(self: *Self) ?T {
            const result = self.current;
            self.current += 1;
            return result;
        }

        pub fn iter(self: *Self) Iter(T) {
            return Iter(T).init(self);
        }
    };
}

test "Counter" {
    var counter = Counter(u32).init(0);
    const iter = counter.iter();

    try std.testing.expectEqual(@as(u32, 0), iter.next().?);
    try std.testing.expectEqual(@as(u32, 1), iter.next().?);
    try std.testing.expectEqual(@as(u32, 2), iter.next().?);
    try std.testing.expectEqual(@as(u32, 3), iter.next().?);
    try std.testing.expectEqual(@as(u32, 4), iter.next().?);
}

pub fn SliceIter(comptime T: type) type {
    return struct {
        const Self = @This();

        slice: []const T,
        index: usize,

        pub fn init(slice: []const T) Self {
            return .{ .slice = slice, .index = 0 };
        }

        pub fn next(self: *Self) ?T {
            if (self.index >= self.slice.len) return null;
            self.index += 1;
            return self.slice[self.index - 1];
        }

        pub fn iter(self: *Self) Iter(T) {
            return Iter(T).init(self);
        }
    };
}

test "Counter" {
    var slice_iter = SliceIter(u32).init(&.{ 1, 2, 3 });
    const iter = slice_iter.iter();

    try std.testing.expectEqual(@as(?u32, 1), iter.next());
    try std.testing.expectEqual(@as(?u32, 2), iter.next());
    try std.testing.expectEqual(@as(?u32, 3), iter.next());
    try std.testing.expectEqual(@as(?u32, null), iter.next());
    try std.testing.expectEqual(@as(?u32, null), iter.next());
}

pub fn Range(comptime T: type) type {
    return struct {
        const Self = @This();

        start: T,
        end: T,
        step: T,

        pub fn init(start: T, end: T) Self {
            return initStep(start, end, 1);
        }

        pub fn initStep(start: T, end: T, step: T) Self {
            return .{ .start = start, .end = end, .step = step };
        }

        pub fn next(self: *Self) ?T {
            if (self.start >= self.end) return null;
            const result = self.start;
            self.start += self.step;
            return result;
        }

        pub fn iter(self: *Self) Iter(T) {
            return Iter(T).init(self);
        }
    };
}

test "Range" {
    var range = Range(u32).initStep(0, 10, 3);
    const iter = range.iter();

    try std.testing.expectEqual(@as(?u32, 0), iter.next());
    try std.testing.expectEqual(@as(?u32, 3), iter.next());
    try std.testing.expectEqual(@as(?u32, 6), iter.next());
    try std.testing.expectEqual(@as(?u32, 9), iter.next());
    try std.testing.expectEqual(@as(?u32, null), iter.next());
    try std.testing.expectEqual(@as(?u32, null), iter.next());
}

pub fn Transform(comptime S: type, comptime T: type) type {
    return struct {
        const Self = @This();

        source: Iter(S),
        op: fn (S) T,

        pub fn init(source: Iter(S), op: fn (S) T) Self {
            return .{ .source = source, .op = op };
        }

        pub fn next(self: *Self) ?T {
            return self.op(self.source.next() orelse return null);
        }

        pub fn iter(self: *Self) Iter(T) {
            return Iter(T).init(self);
        }
    };
}

test "Transform" {
    var op = struct {
        fn op(x: u32) u32 {
            return x * x;
        }
    }.op;

    var range = Range(u32).initStep(0, 10, 3);
    var transform = Transform(u32, u32).init(range.iter(), op);
    const iter = transform.iter();

    try std.testing.expectEqual(@as(?u32, 0), iter.next());
    try std.testing.expectEqual(@as(?u32, 9), iter.next());
    try std.testing.expectEqual(@as(?u32, 36), iter.next());
    try std.testing.expectEqual(@as(?u32, 81), iter.next());
    try std.testing.expectEqual(@as(?u32, null), iter.next());
    try std.testing.expectEqual(@as(?u32, null), iter.next());
}

pub fn Filter(comptime T: type) type {
    return struct {
        const Self = @This();

        source: Iter(T),
        pred: fn (T) bool,

        pub fn init(source: Iter(T), pred: fn (T) bool) Self {
            return .{ .source = source, .pred = pred };
        }

        pub fn next(self: *Self) ?T {
            while (true) {
                const source = self.source.next() orelse return null;
                if (self.pred(source)) return source;
            }
        }

        pub fn iter(self: *Self) Iter(T) {
            return Iter(T).init(self);
        }
    };
}

test "Filter" {
    var pred = struct {
        fn pred(x: u32) bool {
            return x % 2 == 0;
        }
    }.pred;

    var range = Range(u32).init(0, 10);
    var filter = Filter(u32).init(range.iter(), pred);
    const iter = filter.iter();

    try std.testing.expectEqual(@as(?u32, 0), iter.next());
    try std.testing.expectEqual(@as(?u32, 2), iter.next());
    try std.testing.expectEqual(@as(?u32, 4), iter.next());
    try std.testing.expectEqual(@as(?u32, 6), iter.next());
    try std.testing.expectEqual(@as(?u32, 8), iter.next());
    try std.testing.expectEqual(@as(?u32, null), iter.next());
    try std.testing.expectEqual(@as(?u32, null), iter.next());
}

pub fn Enumerate(comptime T: type) type {
    return struct {
        pub const ReturnType = std.meta.Tuple(&.{ usize, T });

        const Self = @This();

        source: Iter(T),
        count: usize,

        pub fn init(source: Iter(T)) Self {
            return .{ .source = source, .count = 0 };
        }

        pub fn next(self: *Self) ?ReturnType {
            const source = self.source.next() orelse return null;
            const count = self.count;
            self.count += 1;
            return ReturnType{ count, source };
        }

        pub fn iter(self: *Self) Iter(ReturnType) {
            return Iter(ReturnType).init(self);
        }
    };
}

test "Enumerate" {
    var range = Range(u32).init(1, 5);
    var enumerate = Enumerate(u32).init(range.iter());
    const iter = enumerate.iter();

    try std.testing.expectEqual(Enumerate(u32).ReturnType{ 0, 1 }, iter.next().?);
    try std.testing.expectEqual(Enumerate(u32).ReturnType{ 1, 2 }, iter.next().?);
    try std.testing.expectEqual(Enumerate(u32).ReturnType{ 2, 3 }, iter.next().?);
    try std.testing.expectEqual(Enumerate(u32).ReturnType{ 3, 4 }, iter.next().?);
    try std.testing.expectEqual(@as(?Enumerate(u32).ReturnType, null), iter.next());
    try std.testing.expectEqual(@as(?Enumerate(u32).ReturnType, null), iter.next());
}
