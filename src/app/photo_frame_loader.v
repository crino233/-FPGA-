`timescale 1ns/1ps
module photo_frame_loader #(
    parameter integer image_width = 640,
    parameter integer image_height = 480,
    parameter integer fifo_depth = 512,
    parameter integer burst_words = 128,
    parameter integer stall_cycles = 1250000,
    parameter integer arbitrated = 0
) (
    input wire clk, input wire rst_n, input wire load_start,
    input wire [1:0] image_index, input wire pixel_valid,
    input wire [23:0] pixel_data, input wire top_down, input wire frame_commit, input wire load_end,
    input wire load_cancel,
    input wire [7:0] decode_error, input wire [7:0] upstream_error,
    input wire controller_ready, input wire controller_busy, input wire refresh_active,
    input wire memory_grant, output wire memory_request, output reg memory_done,
    output wire load_busy, output reg load_done, output wire pixel_ready,
    output reg [3:0] image_complete, output reg [7:0] error_code,
    output reg app_wr_en, output reg [20:0] app_wr_addr,
    output reg [31:0] app_wr_data, output wire [3:0] app_wr_mask
);
    localparam integer image_words = image_width*image_height;
    localparam integer ptr_bits = $clog2(fifo_depth);
    localparam integer count_bits = $clog2(image_words+1);
    localparam integer column_bits = $clog2(image_width);
    localparam integer burst_bits = $clog2(burst_words+1);
    localparam integer stall_bits = $clog2(stall_cycles+1);
    reg active_flag, commit_flag, cancel_flag;
    reg [1:0] active_index;
    reg [31:0] fifo_buf [0:fifo_depth-1];
    reg [ptr_bits-1:0] write_index, read_index;
    reg [ptr_bits:0] fifo_count;
    reg [count_bits-1:0] received_count, written_count;
    reg [stall_bits-1:0] stall_tick;
    reg [20:0] row_addr;
    reg [column_bits-1:0] column_index;
    reg [burst_bits-1:0] burst_left;
    reg [4:0] gap_tick;
    reg burst_active;
    wire pop_flag = active_flag && burst_left != 0;
    wire push_flag = active_flag && !load_cancel && !cancel_flag && pixel_valid &&
        (fifo_count < fifo_depth || pop_flag);
    wire [20:0] bank_addr = active_index*image_words;
    assign load_busy = active_flag;
    assign pixel_ready = active_flag && !load_cancel && !cancel_flag && error_code == 0 &&
        (fifo_count < fifo_depth || pop_flag);
    assign memory_request = active_flag && !burst_active && error_code == 0 && gap_tick == 0 &&
        (fifo_count >= burst_words || (commit_flag && fifo_count != 0));
    assign app_wr_mask = 0;
    always @(posedge clk) begin
        if (push_flag) fifo_buf[write_index] <= {8'd0,pixel_data};
        if (pop_flag) app_wr_data <= fifo_buf[read_index];
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active_flag <= 0; commit_flag <= 0; cancel_flag <= 0; active_index <= 0;
            write_index <= 0; read_index <= 0; fifo_count <= 0;
            received_count <= 0; written_count <= 0; stall_tick <= 0;
            row_addr <= 0; column_index <= 0; burst_left <= 0; gap_tick <= 0;
            load_done <= 0; image_complete <= 0; error_code <= 0;
            app_wr_en <= 0; app_wr_addr <= 0;
            burst_active <= 0; memory_done <= 0;
        end else begin
            load_done <= 0; app_wr_en <= pop_flag; memory_done <= 0;
            if(arbitrated && memory_grant && !memory_request) memory_done <= 1;
            if (gap_tick != 0) gap_tick <= gap_tick-1'b1;
            if (load_start && !active_flag) begin
                active_flag <= 1; commit_flag <= 0; cancel_flag <= 0; active_index <= image_index;
                write_index <= 0; read_index <= 0; fifo_count <= 0;
                received_count <= 0; written_count <= 0; stall_tick <= 0;
                row_addr <= 0; column_index <= 0; burst_left <= 0; gap_tick <= 0;
                image_complete[image_index] <= 0; error_code <= 0;
            end else if (active_flag) begin
                if (frame_commit || (load_end &&
                    (decode_error != 0 || upstream_error != 0 || error_code != 0)))
                    commit_flag <= 1;
                if(load_cancel)begin cancel_flag<=1;commit_flag<=1;end
                if(!load_cancel && !cancel_flag)begin
                    if (decode_error != 0 || upstream_error != 0) error_code <= 8'h44;
                    else if (pixel_valid && received_count >= image_words) error_code <= 8'h43;
                    else if (pixel_valid && !push_flag) error_code <= 8'h42;
                end
                if (push_flag) begin
                    write_index <= write_index+1'b1;
                    received_count <= received_count+1'b1;
                    if (received_count == 0)
                        row_addr <= top_down ? 0 : image_words-image_width;
                end
                if (pop_flag) begin
                    app_wr_addr <= bank_addr+row_addr+column_index;
                    read_index <= read_index+1'b1;
                    written_count <= written_count+1'b1;
                    burst_left <= burst_left-1'b1;
                    if (column_index == image_width-1) begin
                        column_index <= 0;
                        row_addr <= top_down ? row_addr+image_width : row_addr-image_width;
                    end else column_index <= column_index+1'b1;
                    if (burst_left == 1) gap_tick <= 16;
                end else if (memory_request && controller_ready &&
                    (arbitrated ? memory_grant : (!controller_busy && !refresh_active))) begin
                    burst_left <= fifo_count >= burst_words ? burst_words : fifo_count;
                    burst_active <= 1;
                end
                if (burst_active && burst_left == 0 && !app_wr_en && gap_tick == 0 && !controller_busy) begin
                    burst_active <= 0; memory_done <= 1;
                end
                case ({push_flag,pop_flag})
                    2'b10: fifo_count <= fifo_count+1'b1;
                    2'b01: fifo_count <= fifo_count-1'b1;
                    default: ;
                endcase
                if ((fifo_count >= burst_words || (commit_flag && fifo_count != 0)) &&
                    !pop_flag && error_code == 0) begin
                    if (stall_tick == stall_cycles) error_code <= 8'h46;
                    else stall_tick <= stall_tick+1'b1;
                end else stall_tick <= 0;
                if (burst_left == 0 && !app_wr_en && gap_tick == 0 && !controller_busy) begin
                    if (error_code != 0 && commit_flag) begin active_flag <= 0; load_done <= 1; end
                    else if (commit_flag && fifo_count == 0) begin
                        active_flag <= 0; load_done <= 1;
                        if(cancel_flag || load_cancel) image_complete[active_index]<=0;
                        else if (received_count == image_words && written_count == image_words)
                            image_complete[active_index] <= 1;
                        else error_code <= 8'h45;
                    end
                end
            end
        end
    end
endmodule
