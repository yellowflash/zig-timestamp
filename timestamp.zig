const std = @import("std");

const MillisInADay = 24 * 60 * 60 * 1000;

const DMY = struct { d: u16, m: u16, y: u32 };

const DateFormat = enum { @"dd-MM-yyyy", @"dd-MMM-yyyy", ddMMMyy, @"yyyy-MM-dd" };

pub fn binarySearch(
    comptime T: type,
    key: anytype,
    items: []const T,
    context: anytype,
    comptime compareFn: fn (context: @TypeOf(context), key: @TypeOf(key), mid_item: T) std.math.Order,
) usize {
    var left: usize = 0;
    var right: usize = items.len;

    while (left < right) {
        // Avoid overflowing in the midpoint calculation
        const mid = left + (right - left) / 2;
        // Compare the key with the midpoint element
        switch (compareFn(context, key, items[mid])) {
            .eq => return mid,
            .gt => left = mid + 1,
            .lt => right = mid,
        }
    }

    // Copied from stdlib, except stdlib returns null here, I would like previous value.
    return if (left < items.len and
        (compareFn(context, items[left], key) == std.math.Order.lt)) left else right;
}

pub const Month = enum {
    jan,
    feb,
    mar,
    apr,
    may,
    jun,
    jul,
    aug,
    sep,
    oct,
    nov,
    dec,

    const Names = [_]*const [3:0]u8{ "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC" };

    pub fn str(self: Month) [3]u8 {
        return Month.Names[@intFromEnum(self)].*;
    }
};

pub const DayOfTheWeek = enum { monday, tuesday, wednesday, thursday, friday, saturday, sunday };

pub const TimeOfTheDay = struct {
    epoch: u64,

    fn new(hour: u16, minute: u16, second: u16, millis: u16) TimeOfTheDay {
        return .{ .epoch = millis + (second + (minute + (@as(u64, hour) * 60)) * 60) * 1000 };
    }
};

pub const BusinessDays = struct {
    holidays: []Date,
    weekendWorkingDays: []Date,

    pub fn new(holidays: []Date, weekendWorkingDays: []Date) BusinessDays {
        // std.sort.insertion(Date, holidays, Date, lessThan);
        // std.sort.insertion(Date, weekendWorkingDays, Date, lessThan);
        return .{ .holidays = holidays, .weekendWorkingDays = weekendWorkingDays };
    }

    fn countOddWorkingDays(self: *const BusinessDays, left: Date, right: Date) usize {
        var count: usize = 0;
        var i: usize = 0;
        while (i < self.weekendWorkingDays.len) : (i += 1) {
            const current = self.weekendWorkingDays[i];
            if (compare(Date, current, left) == std.math.Order.lt) {
                continue;
            }
            if (compare(Date, current, right) == std.math.Order.gt) {
                break;
            }
            count += 1;
        }
        return count;
    }

    // Counts days exclusive of left and right.
    pub fn between(self: *const BusinessDays, left: Date, right: Date) usize {
        const numDays: usize = (right.epochDays - left.epochDays);
        const weekEnds: usize = switch (left.dayOfTheWeek()) {
            .monday => (numDays / 7) * 2 + (if (numDays % 7 > 4) @min(numDays % 7 - 4, 2) else 0),
            .tuesday => (numDays / 7) * 2 + (if (numDays % 7 > 3) @min(numDays % 7 - 3, 2) else 0),
            .wednesday => (numDays / 7) * 2 + (if (numDays % 7 > 3) @min(numDays % 7 - 2, 2) else 0),
            .thursday => (numDays / 7) * 2 + (if (numDays % 7 > 3) @min(numDays % 7 - 1, 2) else 0),
            .friday => (numDays / 7) * 2 + (if (numDays % 7 > 0) @min(numDays % 7, 2) else 0),
            .saturday => 1 + (numDays / 7) * 2 + @intFromBool(numDays % 7 > 0),
            .sunday => 1 + (numDays / 7) * 2 + @intFromBool(numDays % 7 > 5),
        };
        const start = binarySearch(Date, left, self.holidays, Date, compare);
        var end: i64 = @intCast(binarySearch(Date, right, self.holidays, Date, compare));
        const oddWorkingDays = self.countOddWorkingDays(left, right);

        if (end < self.holidays.len and compare(Date, self.holidays[@intCast(end)], right) == std.math.Order.gt) {
            end -= 1;
        }
        return numDays - weekEnds - (if (end < start) 0 else @as(u64, @intCast(end)) - start + 1) + oddWorkingDays;
    }
};

pub const Date = struct {
    epochDays: u64,

    // http://howardhinnant.github.io/date_algorithms.html
    fn new(date: u16, month: Month, year: u32) Date {
        const m = @intFromEnum(month) + 1;
        const y = year - @intFromBool(m <= 2);
        const era: u64 = @divTrunc(y, 400); // Original allows negative years, ie., years before 1970 ignoring here.
        const yoe: u64 = y - era * 400;
        const doy: u64 = (@as(u64, 153) * (if (m > 2) m - 3 else m + 9) + 2) / 5 + (date - 1);
        const doe: u64 = yoe * 365 + yoe / 4 - yoe / 100 + doy;
        return .{ .epochDays = era * 146097 + doe - 719468 };
    }

    fn dmy(self: Date) DMY {
        const z = self.epochDays + 719468;
        const era = @divTrunc(z, 146097); // Original handles the case this overflow, here I am ignoring the possibility
        const doe = z - era * 146097;
        const yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
        const y = yoe + era * 400;
        const doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
        const mp = (5 * doy + 2) / 153;
        const d = doy - (153 * mp + 2) / 5 + 1;
        const m = if (mp < 10) mp + 3 else mp - 9;
        return .{ .d = @intCast(d), .m = @intCast(m), .y = @intCast(y + @intFromBool(m <= 2)) };
    }

    fn at(self: Date, time: TimeOfTheDay) Timestamp {
        return Timestamp.new(self.epochDays * MillisInADay + time);
    }

    fn dayOfTheWeek(self: Date) DayOfTheWeek {
        return @enumFromInt((self.epochDays + 4) % 7);
    }

    pub fn format(self: Date, comptime fmt: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        const f = std.meta.stringToEnum(DateFormat, fmt);

        if (f) |_format| {
            const _dmy = self.dmy();

            try switch (_format) {
                .@"dd-MM-yyyy" => writer.print("{d:0>2}-{d:0>2}-{d:0>4}", .{ _dmy.d, _dmy.m, _dmy.y }),
                .@"dd-MMM-yyyy" => writer.print("{d:0>2}-{s}-{d:0>4}", .{ _dmy.d, @as(Month, @enumFromInt(_dmy.m - 1)).str(), _dmy.y }),
                .ddMMMyy => writer.print("{d:0>2}{s}{d:0>2}", .{ _dmy.d, @as(Month, @enumFromInt(_dmy.m - 1)).str(), (_dmy.y % 2000) }),
                .@"yyyy-MM-dd" => writer.print("{d:0>4}-{d:0>2}-{d:0>2}", .{ _dmy.y, _dmy.m, _dmy.d }),
            };
        } else {
            unreachable;
        }
    }
};

pub const Timestamp = struct {
    epoch: u64,

    pub fn new(epoch: u64) Timestamp {
        return .{ .epoch = epoch };
    }

    pub fn date(self: Timestamp) Date {
        return .{ .epochDays = @divTrunc(self.epoch, MillisInADay) };
    }

    pub fn timeOfTheDay(self: Timestamp) TimeOfTheDay {
        return .{ .epoch = self.epoch % MillisInADay };
    }
};

fn compare(comptime T: type, left: T, right: T) std.math.Order {
    if (comptime std.meta.eql(T, Date)) {
        return std.math.order(left.epochDays, right.epochDays);
    } else if (comptime std.meta.eql(T, Timestamp)) {
        return std.math.order(left.epoch, right.epoch);
    } else if (comptime std.meta.eql(T, TimeOfTheDay)) {
        return std.math.order(left.epoch, right.epoch);
    } else {
        var slice: [64]u8 = undefined;
        @compileError(std.fmt.bufPrint(&slice, "lessThan not supported for {}", .{T}) catch {});
    }
}

fn lessThan(comptime T: type, left: T, right: T) bool {
    return compare(T, left, right) == std.math.Order.lt;
}

test "date from d m y and back again" {
    try std.testing.expectEqual(
        DMY{ .d = 1, .m = 1, .y = 2024 },
        Date.new(1, Month.jan, 2024).dmy(),
    );
    try std.testing.expectEqual(
        DMY{ .d = 31, .m = 3, .y = 2019 },
        Date.new(31, Month.mar, 2019).dmy(),
    );
}

test "date format test" {
    const date = Date.new(1, Month.feb, 2019);
    var slice: [32]u8 = undefined;

    try std.testing.expectEqualStrings(
        "01-02-2019",
        try std.fmt.bufPrint(&slice, "{dd-MM-yyyy}", .{date}),
    );

    try std.testing.expectEqualStrings("01-FEB-2019", try std.fmt.bufPrint(&slice, "{dd-MMM-yyyy}", .{date}));

    try std.testing.expectEqualStrings("01FEB19", try std.fmt.bufPrint(&slice, "{ddMMMyy}", .{date}));

    try std.testing.expectEqualStrings("2019-02-01", try std.fmt.bufPrint(&slice, "{yyyy-MM-dd}", .{date}));
}

test "can compare" {
    try std.testing.expect(lessThan(Date, Date.new(1, Month.feb, 2020), Date.new(2, Month.mar, 2021)));
    try std.testing.expect(lessThan(Timestamp, Timestamp.new(1), Timestamp.new(2)));
    try std.testing.expect(lessThan(TimeOfTheDay, TimeOfTheDay.new(10, 30, 0, 0), TimeOfTheDay.new(12, 30, 0, 0)));
}

test "count business days" {
    var holidays = [1]Date{Date.new(1, Month.may, 2024)};
    var weekendWorkingDays = [1]Date{Date.new(5, Month.may, 2024)};
    const businessDays = BusinessDays.new(&holidays, &weekendWorkingDays);

    try std.testing.expectEqual(2, businessDays.between(Date.new(26, Month.apr, 2024), Date.new(2, Month.may, 2024)));
    try std.testing.expectEqual(5, businessDays.between(Date.new(26, Month.apr, 2024), Date.new(6, Month.may, 2024)));
    try std.testing.expectEqual(0, businessDays.between(Date.new(27, Month.apr, 2024), Date.new(28, Month.apr, 2024)));
    try std.testing.expectEqual(1, businessDays.between(Date.new(26, Month.apr, 2024), Date.new(29, Month.apr, 2024)));
    try std.testing.expectEqual(1, businessDays.between(Date.new(27, Month.apr, 2024), Date.new(29, Month.apr, 2024)));
}
