const std = @import("std");

const MillisInADay = 24 * 60 * 60 * 1000;

const DMY = struct { d: u16, m: u16, y: u32 };

const DateFormat = enum { @"dd-MM-yyyy", @"dd-MMM-yyyy", ddMMMyy, @"yyyy-MM-dd" };

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

pub const TimeOfTheDay = struct { epoch: u64 };

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
