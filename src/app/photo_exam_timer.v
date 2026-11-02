`timescale 1ns/1ps
module photo_exam_timer (
    input wire clk,
    input wire rst_n,
    input wire tick_1ms,
    input wire exam_enable,
    input wire pause_active,
    input wire start_toggle,
    input wire duration_step,
    input wire reset_cmd,
    input wire pause_cmd,
    input wire [2:0] duration_index,
    output reg [31:0] remaining_seconds,
    output reg [15:0] remaining_minutes,
    output reg [5:0] remaining_second,
    output reg running,
    output reg finished
);
    reg [9:0] millisecond_count;

    function [31:0] duration_seconds;
        input [2:0] index;
        begin
            case (index)
                3'd0: duration_seconds = 32'd1800;
                3'd1: duration_seconds = 32'd3600;
                3'd2: duration_seconds = 32'd5400;
                3'd3: duration_seconds = 32'd7200;
                3'd4: duration_seconds = 32'd9000;
                3'd6: duration_seconds = 32'd60;
                default: duration_seconds = 32'd10800;
            endcase
        end
    endfunction

    task set_duration;
        input [31:0] seconds_value;
        begin
            remaining_seconds <= seconds_value;
            remaining_minutes <= seconds_value / 60;
            remaining_second <= seconds_value % 60;
            millisecond_count <= 0;
            running <= 0;
            finished <= 0;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            remaining_seconds <= 32'd1800;
            remaining_minutes <= 16'd30;
            remaining_second <= 0;
            millisecond_count <= 0;
            running <= 0;
            finished <= 0;
        end else if (!exam_enable) begin
            set_duration(duration_seconds(duration_index));
        end else if (reset_cmd) begin
            set_duration(duration_seconds(duration_index));
        end else if (duration_step && !running && !finished) begin
            set_duration(duration_seconds(duration_index));
        end else if (pause_active || pause_cmd) begin
            running <= 0;
        end else if (start_toggle && !finished) begin
            running <= !running;
        end else if (running && tick_1ms) begin
            if (millisecond_count == 10'd999) begin
                millisecond_count <= 0;
                if (remaining_seconds <= 1) begin
                    remaining_seconds <= 0;
                    remaining_minutes <= 0;
                    remaining_second <= 0;
                    running <= 0;
                    finished <= 1;
                end else begin
                    remaining_seconds <= remaining_seconds - 1'b1;
                    if (remaining_second == 0) begin
                        remaining_minutes <= remaining_minutes - 1'b1;
                        remaining_second <= 6'd59;
                    end else begin
                        remaining_second <= remaining_second - 1'b1;
                    end
                end
            end else millisecond_count <= millisecond_count + 1'b1;
        end
    end
endmodule
