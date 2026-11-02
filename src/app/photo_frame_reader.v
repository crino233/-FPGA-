`timescale 1ns/1ps
module photo_frame_reader #(
    parameter integer image_words = 307200,
    parameter integer burst_words = 128,
    parameter integer arbitrated = 0
) (
    input wire mem_clk, input wire mem_rst_n,
    input wire pix_clk, input wire pix_rst_n,
    input wire display_ready, input wire [1:0] image_index,
    input wire controller_ready, input wire controller_busy, input wire refresh_active,
    input wire memory_grant, output wire memory_request, output reg memory_done,
    output reg app_rd_en, output reg [20:0] app_rd_addr,
    input wire sdram_rd_valid, input wire [31:0] sdram_rd_data,
    input wire frame_sync, input wire read_req, output wire read_req_ack,
    input wire read_en, output wire [31:0] read_data,
    output reg underflow_flag, output reg [7:0] error_code,
    output reg frame_commit, output reg [1:0] active_index,
    output reg frame_ready
);
    localparam [2:0] st_idle=0, st_ack=1, st_settle=2,
        st_check=3, st_burst=4, st_drain=5;
    reg [2:0] state;
    reg [1:0] request_sync, ack_sync, ready_sync, clear_sync, start_sync;
    reg ack_mem, fifo_clear, pixel_armed, frame_sync_old, start_flag;
    reg prefetch_mem;
    reg [1:0] prefetch_sync;
    reg [20:0] bank_addr, issued_count, returned_count;
    reg [15:0] burst_left;
    reg [4:0] gap_tick;
    reg [17:0] stall_tick;
    wire fifo_empty, fifo_full;
    wire [8:0] fifo_used;
    wire fifo_reset = !mem_rst_n || !pix_rst_n || fifo_clear;
    assign memory_request = state == st_check && !request_sync[1] &&
        issued_count < image_words && fifo_used <= 511-burst_words-8;

    function [20:0] bank_base;
        input [1:0] index;
        begin
            case (index)
                2'd0: bank_base = 21'd0;
                2'd1: bank_base = image_words;
                2'd2: bank_base = image_words * 2;
                default: bank_base = image_words * 3;
            endcase
        end
    endfunction

    assign read_req_ack = ack_sync[1];
    always @(posedge pix_clk or negedge pix_rst_n) begin
        if (!pix_rst_n) begin
            ack_sync <= 0; ready_sync <= 0; clear_sync <= 3; prefetch_sync <= 0;
            pixel_armed <= 0; frame_ready <= 0;
            underflow_flag <= 0; frame_sync_old <= 0; start_flag <= 0;
        end else begin
            ack_sync <= {ack_sync[0],ack_mem};
            ready_sync <= {ready_sync[0],display_ready};
            clear_sync <= {clear_sync[0],fifo_clear};
            prefetch_sync <= {prefetch_sync[0],prefetch_mem};
            frame_sync_old <= frame_sync;
            if (!ready_sync[1]) start_flag <= 0;
            else if (frame_sync_old && !frame_sync) start_flag <= 1;
            if (read_req) begin
                pixel_armed <= 0; frame_ready <= 0; underflow_flag <= 0;
            end else if (!ready_sync[1]) begin
                pixel_armed <= 0; frame_ready <= 0; underflow_flag <= 1;
            end else if (prefetch_sync[1] && !clear_sync[1]) begin
                pixel_armed <= 1; frame_ready <= 1; underflow_flag <= 0;
            end else if (read_en && pixel_armed && fifo_empty) begin
                pixel_armed <= 0; frame_ready <= 0; underflow_flag <= 1;
            end
        end
    end
    rfifo_32_32_512 read_fifo (
        .rst(fifo_reset), .clkw(mem_clk), .clkr(pix_clk),
        .we(sdram_rd_valid && state != st_idle && state != st_ack && state != st_settle),
        .di(sdram_rd_data), .re(read_en && pixel_armed && ready_sync[1]),
        .dout(read_data), .valid(), .full_flag(fifo_full), .empty_flag(fifo_empty),
        .afull(), .aempty(), .wrusedw(fifo_used), .rdusedw()
    );
    always @(posedge mem_clk or negedge mem_rst_n) begin
        if (!mem_rst_n) begin
            state <= st_idle; request_sync <= 0; start_sync <= 0; ack_mem <= 0; fifo_clear <= 1;
            bank_addr <= 0; issued_count <= 0; returned_count <= 0;
            burst_left <= 0; gap_tick <= 0; stall_tick <= 0;
            app_rd_en <= 0; app_rd_addr <= 0; error_code <= 0;
            frame_commit <= 0; active_index <= 0; prefetch_mem <= 0;
            memory_done <= 0;
        end else begin
            request_sync <= {request_sync[0],read_req};
            start_sync <= {start_sync[0],start_flag};
            app_rd_en <= 0;
            frame_commit <= 0;
            memory_done <= 0;
            if(arbitrated && memory_grant && !memory_request) memory_done <= 1;
            if (state == st_idle || fifo_clear) prefetch_mem <= 0;
            if (gap_tick != 0) gap_tick <= gap_tick-1'b1;
            if (sdram_rd_valid) begin
                returned_count <= returned_count+1'b1;
                if (returned_count >= 21'd63) prefetch_mem <= 1;
            end
            if (state == st_burst || state == st_drain) stall_tick <= stall_tick+1'b1;
            else stall_tick <= 0;
            case (state)
                st_idle: if (request_sync[1] && start_sync[1] && display_ready && controller_ready &&
                             !controller_busy && !refresh_active && error_code == 0 &&
                             returned_count == issued_count) begin
                    fifo_clear <= 1; ack_mem <= 1; state <= st_ack;
                    bank_addr <= bank_base(image_index);
                    active_index <= image_index; frame_commit <= 1;
                    issued_count <= 0; returned_count <= 0;
                end
                st_ack: if (!request_sync[1]) begin
                    ack_mem <= 0; fifo_clear <= 0; gap_tick <= 12; state <= st_settle;
                end
                st_settle: if (gap_tick == 0) state <= st_check;
                st_check: begin
                    if (request_sync[1]) begin
                        if (issued_count != image_words || returned_count != issued_count)
                            error_code <= 8'h54;
                        state <= st_idle;
                    end
                    else if (memory_request &&
                             (arbitrated ? memory_grant : (!controller_busy && !refresh_active))) begin
                        burst_left <= image_words-issued_count >= burst_words ?
                                      burst_words : image_words-issued_count;
                        state <= st_burst;
                    end
                end
                st_burst: begin
                    app_rd_en <= 1; app_rd_addr <= bank_addr+issued_count;
                    issued_count <= issued_count+1'b1; burst_left <= burst_left-1'b1;
                    if (burst_left == 1) begin gap_tick <= 16; state <= st_drain; end
                end
                st_drain: if (gap_tick == 0 && returned_count == issued_count &&
                             !controller_busy) begin state <= st_check; memory_done <= 1; end
                default: begin error_code <= 8'h5f; state <= st_idle; end
            endcase
            if (sdram_rd_valid && fifo_full) begin error_code <= 8'h52; state <= st_idle; end
            if (stall_tick == 18'h3ffff) begin error_code <= 8'h53; state <= st_idle; end
        end
    end
endmodule
