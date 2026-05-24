const std = @import("std");
const expect = std.testing.expect;

fn compute_encode_length(input: []const u8) !usize {
    if (input.len < 3) {
        return 4;
    }

    const n_groups: usize = try std.math.divCeil(usize, input.len, 3);
    return n_groups * 4;
}

fn compute_decode_length(input: []const u8) !usize {
    if (input.len < 4) {
        return 3;
    }

    const n_groups = try std.math.divCeil(usize, input.len, 4);
    var groups = n_groups * 3;
    var i: usize = input.len - 1;
    while (i > 0) : (i -= 1) {
        if (input[i] == '=') {
            groups -= 1;
        } else {
            break;
        }
    }

    return groups;
}

pub const Base64 = struct {
    // Table from index to char.
    _table: *const [64]u8,
    // Table from char to index.
    // _inv_table: *const [64]u8,

    pub fn init() Base64 {
        const upper = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
        const lower = "abcdefghijklmnopqrstuvwxyz";
        const numbers_symb = "0123456789+/";
        const _table = upper ++ lower ++ numbers_symb;

        return .{ ._table = _table };
    }

    /// Encode binary data in base64 format.
    pub fn encode(self: Base64, allocator: std.mem.Allocator, input: []const u8) ![]u8 {
        // We need to iterate to group of 3 bytes. Because the input could be not divisible by 3,
        // we need to pay attention to 3 cases:
        // 1) we get 3 bytes and we can perform a complete step without problems.
        // 2) we get 2 bytes and we need to add some padding.
        // 3) we get 1 byte and we need to add some padding.

        if (input.len == 0) {
            return "";
        }

        const size = try compute_encode_length(input);
        const output = try allocator.alloc(u8, size);

        var count: usize = 0;
        var current_block: usize = 0;
        var output_idx: usize = 0;
        var i: usize = 0;
        while (i < input.len) : (i += 1) {
            count += 1;
            if (count == 3) {
                count = 0;
                const out0 = input[current_block] >> 2;
                const out1 = ((input[current_block] & 0b11) << 4) | ((input[current_block + 1] & 0b11110000) >> 4);
                const out2 = ((input[current_block + 1] & 0b1111) << 2) | ((input[current_block + 2] & 0b11000000) >> 6);
                const out3 = input[current_block + 2] & 0b00111111;

                output[output_idx + 0] = self._char_at(out0);
                output[output_idx + 1] = self._char_at(out1);
                output[output_idx + 2] = self._char_at(out2);
                output[output_idx + 3] = self._char_at(out3);
                output_idx += 4;
                current_block += 3;
            }
        }

        current_block = i - count;
        if (count == 2) {
            const out0 = input[current_block] >> 2;
            const out1 = ((input[current_block] & 0b11) << 4) | ((input[current_block + 1] & 0b11110000) >> 4);
            const out2 = (input[current_block + 1] & 0b00001111) << 2;
            const out3 = '=';

            output[output_idx + 0] = self._char_at(out0);
            output[output_idx + 1] = self._char_at(out1);
            output[output_idx + 2] = self._char_at(out2);
            output[output_idx + 3] = out3;
        } else if (count == 1) {
            const out0 = input[current_block] >> 2;
            const out1 = ((input[current_block] & 0b11) << 4);
            const out2 = '=';
            const out3 = '=';

            output[output_idx + 0] = self._char_at(out0);
            output[output_idx + 1] = self._char_at(out1);
            output[output_idx + 2] = out2;
            output[output_idx + 3] = out3;
        }

        return output;
    }

    /// Decode data in base64 to original binary form.
    pub fn decode(self: Base64, allocator: std.mem.Allocator, input: []const u8) ![]u8 {
        if (input.len == 0) {
            return "";
        }

        const output_size = try compute_decode_length(input);
        const output = try allocator.alloc(u8, output_size);

        var i: usize = 0;
        var out_idx: usize = 0;
        while (i < input.len) : (i += 4) {
            const idx0 = self._char_index(input[i]);
            const idx1 = self._char_index(input[i + 1]);
            const idx2 = self._char_index(input[i + 2]);
            const idx3 = self._char_index(input[i + 3]);

            const out0 = (idx0 << 2) | (idx1 >> 4);
            const out1 = (idx1 << 4) | (idx2 >> 2);
            const out2 = (idx2 << 6) | idx3;

            output[out_idx + 0] = out0;
            if (out1 == 64) {
                break;
            }
            output[out_idx + 1] = out1;

            if (out2 == 64) {
                break;
            }
            output[out_idx + 2] = out2;

            out_idx += 3;
        }

        return output;
    }

    /// Get the char associated to the index.
    pub fn _char_at(self: Base64, index: usize) u8 {
        return self._table[index];
    }

    /// Get the index that produces the char.
    pub fn _char_index(self: Base64, char: u8) u8 {
        if (char == '=') {
            return 64;
        }

        var out_idx: u8 = 0;
        for (0..64) |i| {
            if (char == self._char_at(i)) {
                break;
            }
            out_idx += 1;
        }
        return out_idx;
    }
};

test "test base64 encode" {
    const gpa = std.testing.allocator;
    var encoder = Base64.init();

    const s = "hello world";

    const output = try encoder.encode(gpa, s);
    defer gpa.free(output);

    try std.testing.expectEqualStrings(output, "aGVsbG8gd29ybGQ=");
    // try expect(std.mem.eql(u8, output, "aGVsbG8gd29ybGQ="));
}

test "test base64 decode" {
    const gpa = std.testing.allocator;
    var base = Base64.init();

    const s = "hello world";

    const encoded = try base.encode(gpa, s);
    defer gpa.free(encoded);

    const decoded = try base.decode(gpa, encoded);
    defer gpa.free(decoded);

    try std.testing.expectEqualStrings(s, decoded);
}
