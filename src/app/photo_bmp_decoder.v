`timescale 1ns/1ps
module photo_bmp_decoder #(
    parameter integer image_width = 640,
    parameter integer image_height = 480
) (
    input wire clk, input wire rst_n, input wire file_start,
    input wire [31:0] file_size, input wire file_valid,
    input wire [7:0] file_data, input wire [31:0] file_offset,
    input wire file_end, input wire [7:0] upstream_error,
    output reg pixel_valid, output reg [23:0] pixel_data,
    output reg top_down, output reg frame_commit,
    output reg [7:0] error_code
);
    localparam integer row_stride = (image_width*3+3)/4*4;
    localparam integer image_words = image_width*image_height;
    reg [15:0] signature, planes, bits_per_pixel;
    reg [31:0] declared_size, pixel_offset, dib_size, width_val, height_val, compression;
    reg active_flag, header_flag, end_flag, payload_flag;
    reg signature_invalid, dimensions_invalid, format_invalid, range_invalid, size_invalid;
    reg [31:0] expected_offset, payload_offset;
    reg [$clog2(row_stride)-1:0] row_byte;
    reg [$clog2(image_height+1)-1:0] row_index;
    reg [$clog2(image_words+1)-1:0] pixel_count;
    reg [1:0] color_index;
    reg [7:0] blue_val, green_val;
    reg [32:0] required_size, header_end;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            signature <= 0; planes <= 0; bits_per_pixel <= 0;
            declared_size <= 0; pixel_offset <= 0; dib_size <= 0;
            width_val <= 0; height_val <= 0; compression <= 0;
            active_flag <= 0; header_flag <= 0; end_flag <= 0; payload_flag <= 0;
            payload_offset <= 0;
            expected_offset <= 0; row_byte <= 0; row_index <= 0; pixel_count <= 0;
            color_index <= 0; blue_val <= 0; green_val <= 0;
            pixel_valid <= 0; pixel_data <= 0; top_down <= 0;
            frame_commit <= 0; error_code <= 0;
            required_size <= 0; header_end <= 0;
            signature_invalid <= 1; dimensions_invalid <= 1; format_invalid <= 1;
            range_invalid <= 1; size_invalid <= 1;
        end else begin
            pixel_valid <= 0; frame_commit <= 0;
            required_size <= {1'b0,pixel_offset}+row_stride*image_height;
            header_end <= {1'b0,dib_size}+14;
            payload_offset <= pixel_offset-1'b1;
            signature_invalid <= signature != 16'h4d42;
            dimensions_invalid <= width_val != image_width ||
                (height_val != image_height && height_val != -image_height) || dib_size < 40;
            format_invalid <= planes != 1 || bits_per_pixel != 24 || compression != 0;
            range_invalid <= {1'b0,pixel_offset} < header_end || required_size[32];
            size_invalid <= required_size > file_size || declared_size < required_size || declared_size > file_size;
            if (file_start) begin
                signature <= 0; planes <= 0; bits_per_pixel <= 0;
                declared_size <= 0; pixel_offset <= 0; dib_size <= 0;
                width_val <= 0; height_val <= 0; compression <= 0;
                active_flag <= 1; header_flag <= 0; end_flag <= 0; payload_flag <= 0;
                expected_offset <= 0; row_byte <= 0; row_index <= 0;
                pixel_count <= 0; color_index <= 0; error_code <= 0; top_down <= 0;
            end else if (active_flag) begin
                if (file_valid && error_code == 0) begin
                    expected_offset <= expected_offset+1'b1;
                    if (file_offset != expected_offset) error_code <= 8'h39;
                    if (file_offset == payload_offset) payload_flag <= 1;
                    if (file_offset[31:6] == 0) case (file_offset[5:0])
                        0: signature[7:0] <= file_data;
                        1: signature[15:8] <= file_data;
                        2: declared_size[7:0] <= file_data;
                        3: declared_size[15:8] <= file_data;
                        4: declared_size[23:16] <= file_data;
                        5: declared_size[31:24] <= file_data;
                        10: pixel_offset[7:0] <= file_data;
                        11: pixel_offset[15:8] <= file_data;
                        12: pixel_offset[23:16] <= file_data;
                        13: pixel_offset[31:24] <= file_data;
                        14: dib_size[7:0] <= file_data;
                        15: dib_size[15:8] <= file_data;
                        16: dib_size[23:16] <= file_data;
                        17: dib_size[31:24] <= file_data;
                        18: width_val[7:0] <= file_data;
                        19: width_val[15:8] <= file_data;
                        20: width_val[23:16] <= file_data;
                        21: width_val[31:24] <= file_data;
                        22: height_val[7:0] <= file_data;
                        23: height_val[15:8] <= file_data;
                        24: height_val[23:16] <= file_data;
                        25: height_val[31:24] <= file_data;
                        26: planes[7:0] <= file_data;
                        27: planes[15:8] <= file_data;
                        28: bits_per_pixel[7:0] <= file_data;
                        29: bits_per_pixel[15:8] <= file_data;
                        30: compression[7:0] <= file_data;
                        31: compression[15:8] <= file_data;
                        32: compression[23:16] <= file_data;
                        33: compression[31:24] <= file_data;
                        default: ;
                    endcase
                    if (file_offset == 53) begin
                        if (signature_invalid) error_code <= 8'h31;
                        else if (dimensions_invalid) error_code <= 8'h32;
                        else if (format_invalid) error_code <= 8'h33;
                        else if (range_invalid) error_code <= 8'h36;
                        else if (size_invalid) error_code <= 8'h37;
                        else begin header_flag <= 1; top_down <= height_val[31]; end
                    end
                    if (header_flag && payload_flag && row_index < image_height) begin
                        if (row_byte < image_width*3) begin
                            case (color_index)
                                0: begin blue_val <= file_data; color_index <= 1; end
                                1: begin green_val <= file_data; color_index <= 2; end
                                2: begin
                                    pixel_data <= {file_data,green_val,blue_val}; pixel_valid <= 1;
                                    pixel_count <= pixel_count+1'b1; color_index <= 0;
                                end
                            endcase
                        end
                        if (row_byte == row_stride-1) begin
                            row_byte <= 0; row_index <= row_index+1'b1; color_index <= 0;
                        end else row_byte <= row_byte+1'b1;
                    end
                end
                if (file_end) end_flag <= 1;
                if (end_flag) begin
                    active_flag <= 0; end_flag <= 0;
                    if (upstream_error != 0) error_code <= 8'h38;
                    else if (error_code == 0) begin
                        if (header_flag && pixel_count == image_words &&
                            expected_offset == file_size && row_index == image_height)
                            frame_commit <= 1;
                        else error_code <= 8'h37;
                    end
                end
            end
        end
    end
endmodule
