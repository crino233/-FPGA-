`timescale 1ns/1ps
module sd_card_reader_reference #(
    parameter integer clk_freq_hz = 125000000,
    parameter integer init_div = 200,
    parameter integer data_div = 4,
    parameter integer max_sector_retries = 1
) (
    input wire clk, input wire rst_n, input wire init_start,
    output reg init_done, output reg card_ready,
    output reg high_capacity, output reg [7:0] error_code,
    input wire sector_req, input wire [31:0] sector_lba,
    output wire sector_busy, output reg sector_valid,
    output reg [7:0] sector_data, output reg [8:0] sector_index,
    output reg sector_done,
    output reg sd_cs_n, output wire sd_sclk, output wire sd_mosi,
    input wire sd_miso
);
    localparam [4:0] st_idle=0, st_power=1, st_power_req=2,
        st_power_wait=3, st_send=4, st_send_wait=5,
        st_response=6, st_response_wait=7, st_extra=8,
        st_extra_wait=9, st_trail=10, st_trail_wait=11,
        st_dispatch=12, st_token=13, st_token_wait=14,
        st_data=15, st_data_wait=16, st_crc=17,
        st_crc_wait=18, st_replay=19, st_finish=20,
        st_recover_req=21, st_recover_wait=22;
    localparam integer recovery_bytes=(clk_freq_hz/10+16*init_div-1)/(16*init_div)+520;
    localparam integer power_bits=$clog2(recovery_bytes);
    localparam [1:0] init_retry_limit=2;
    reg [4:0] state;
    reg byte_start, byte_abort;
    reg [7:0] byte_tx;
    wire byte_busy, byte_done;
    wire [7:0] byte_rx;
    reg [5:0] cmd_index;
    reg [31:0] cmd_arg, response_data;
    reg [2:0] cmd_pos, extra_left;
    reg [4:0] response_tick;
    reg [7:0] response_r1;
    reg [power_bits-1:0] power_bytes;
    reg [1:0] init_retry_count;
    reg [31:0] timeout_tick;
    reg card_v2, reading_flag, crc_phase;
    reg cs_val;
    reg [8:0] data_index, replay_index;
    reg [15:0] data_crc;
    reg [7:0] crc_high;
    reg [1:0] sector_retry_count;
    reg [7:0] sector_buf [0:511];
    wire [15:0] byte_div = card_ready ? data_div : init_div;
    assign sector_busy = state != st_idle;
    sd_spi_byte_reference byte_proc (
        .clk(clk), .rst_n(rst_n && !byte_abort), .start(byte_start),
        .clk_div(byte_div), .tx_data(byte_tx), .miso(sd_miso),
        .busy(byte_busy), .done(byte_done), .rx_data(byte_rx),
        .sclk(sd_sclk), .mosi(sd_mosi)
    );
    function [15:0] crc16_next;
        input [15:0] crc; input [7:0] data;
        reg [15:0] temp; integer i;
        begin
            temp = crc;
            for (i=7; i>=0; i=i-1)
                temp = (temp[15] ^ data[i]) ? (temp << 1) ^ 16'h1021 : temp << 1;
            crc16_next = temp;
        end
    endfunction
    function [7:0] command_data;
        input [2:0] pos;
        begin
            case (pos)
                0: command_data = {2'b01, cmd_index};
                1: command_data = cmd_arg[31:24];
                2: command_data = cmd_arg[23:16];
                3: command_data = cmd_arg[15:8];
                4: command_data = cmd_arg[7:0];
                default: command_data = cmd_index == 0 ? 8'h95 :
                                        cmd_index == 8 ? 8'h87 : 8'hff;
            endcase
        end
    endfunction
    task command_begin;
        input [5:0] index; input [31:0] arg; input [2:0] extra;
        begin
            cmd_index <= index; cmd_arg <= arg; extra_left <= extra;
            cmd_pos <= 0; response_tick <= 0; response_data <= 0;
            cs_val <= 0; state <= st_send;
        end
    endtask
    task fail_proc;
        input [7:0] code;
        begin
            byte_start <= 0; byte_abort <= 1;
            if (!reading_flag && code >= 8'h01 && code <= 8'h07 && init_retry_count < init_retry_limit) begin
                init_retry_count <= init_retry_count+1'b1;
                card_v2 <= 0; power_bytes <= 0; cs_val <= 0; state <= st_recover_req;
            end else begin
                error_code <= code; cs_val <= 1; state <= st_finish;
            end
        end
    endtask
    always @(posedge clk) begin
        if (state == st_data_wait && byte_done) sector_buf[data_index] <= byte_rx;
        if (state == st_replay) sector_data <= sector_buf[replay_index];
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) sd_cs_n <= 1;
        else sd_cs_n <= cs_val;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= st_idle; byte_start <= 0; byte_abort <= 0; byte_tx <= 8'hff;
            cmd_index <= 0; cmd_arg <= 0; cmd_pos <= 0; extra_left <= 0;
            response_tick <= 0; response_r1 <= 8'hff; response_data <= 0;
            power_bytes <= 0; init_retry_count <= 0; timeout_tick <= 0; card_v2 <= 0;
            reading_flag <= 0; crc_phase <= 0; data_index <= 0;
            replay_index <= 0; data_crc <= 0; crc_high <= 0;
            sector_retry_count <= 0;
            init_done <= 0; card_ready <= 0; high_capacity <= 0;
            error_code <= 0; sector_valid <= 0;
            sector_index <= 0; sector_done <= 0; cs_val <= 1;
        end else begin
            byte_start <= 0; byte_abort <= 0;
            init_done <= 0; sector_done <= 0; sector_valid <= 0;
            if (state != st_idle && state != st_replay && state != st_finish)
                timeout_tick <= timeout_tick + 1'b1;
            case (state)
                st_idle: begin
                    cs_val <= 1;
                    if (init_start) begin
                        card_ready <= 0; high_capacity <= 0; error_code <= 0;
                        card_v2 <= 0; timeout_tick <= 0; power_bytes <= 0; init_retry_count <= 0;
                        reading_flag <= 0; state <= st_power;
                    end else if (sector_req) begin
                        reading_flag <= 1; timeout_tick <= 0; error_code <= 0;
                        sector_retry_count <= 0;
                        if (!card_ready) fail_proc(8'h11);
                        else if (!high_capacity && sector_lba[31:23] != 0)
                            fail_proc(8'h12);
                        else command_begin(17, high_capacity ? sector_lba : sector_lba << 9, 0);
                    end
                end
                st_power: if (timeout_tick >= clk_freq_hz/1000) state <= st_power_req;
                st_power_req: if (!byte_busy) begin
                    byte_tx <= 8'hff; byte_start <= 1; state <= st_power_wait;
                end
                st_power_wait: if (byte_done) begin
                    if (power_bytes == 9) command_begin(0, 0, 0);
                    else begin power_bytes <= power_bytes+1'b1; state <= st_power_req; end
                end
                st_recover_req: if (!byte_busy) begin
                    byte_tx <= 8'hff; byte_start <= 1; state <= st_recover_wait;
                end
                st_recover_wait: if (byte_done) begin
                    if (power_bytes == recovery_bytes-1) begin
                        cs_val <= 1; power_bytes <= 0; state <= st_power_req;
                    end else begin power_bytes <= power_bytes+1'b1; state <= st_recover_req; end
                end
                st_send: if (!byte_busy) begin
                    byte_tx <= command_data(cmd_pos); byte_start <= 1; state <= st_send_wait;
                end
                st_send_wait: if (byte_done) begin
                    if (cmd_pos == 5) state <= st_response;
                    else begin cmd_pos <= cmd_pos+1'b1; state <= st_send; end
                end
                st_response: if (!byte_busy) begin
                    byte_tx <= 8'hff; byte_start <= 1; state <= st_response_wait;
                end
                st_response_wait: if (byte_done) begin
                    if (!byte_rx[7]) begin
                        response_r1 <= byte_rx;
                        if (cmd_index == 17 && byte_rx == 0) state <= st_token;
                        else if (extra_left != 0 && !byte_rx[2]) state <= st_extra;
                        else begin cs_val <= 1; state <= st_trail; end
                    end else if (response_tick == 15) fail_proc(8'h01);
                    else begin response_tick <= response_tick+1'b1; state <= st_response; end
                end
                st_extra: if (!byte_busy) begin
                    byte_tx <= 8'hff; byte_start <= 1; state <= st_extra_wait;
                end
                st_extra_wait: if (byte_done) begin
                    response_data <= {response_data[23:0], byte_rx};
                    extra_left <= extra_left-1'b1;
                    if (extra_left == 1) begin cs_val <= 1; state <= st_trail; end
                    else state <= st_extra;
                end
                st_trail: if (!byte_busy) begin
                    byte_tx <= 8'hff; byte_start <= 1; state <= st_trail_wait;
                end
                st_trail_wait: if (byte_done) state <= st_dispatch;
                st_dispatch: case (cmd_index)
                    0: if (response_r1 == 1) command_begin(8, 32'h1aa, 4);
                       else fail_proc(8'h02);
                    8: if (response_r1 == 1 && response_data[11:0] == 12'h1aa) begin
                           card_v2 <= 1; command_begin(55, 0, 0);
                       end else if (response_r1 == 5) command_begin(55, 0, 0);
                       else fail_proc(8'h03);
                    55: if (response_r1 == 1 || response_r1 == 0)
                            command_begin(41, card_v2 ? 32'h40000000 : 0, 0);
                        else fail_proc(8'h04);
                    41: if (response_r1 == 0) command_begin(58, 0, 4);
                        else if (response_r1 == 1) command_begin(55, 0, 0);
                        else fail_proc(8'h05);
                    58: if (response_r1 != 0 || !response_data[31] || response_data[23:15] == 0)
                            fail_proc(8'h06);
                        else if (card_v2 && response_data[30]) begin
                            high_capacity <= 1; card_ready <= 1; state <= st_finish;
                        end else command_begin(16, 512, 0);
                    16: if (response_r1 == 0) begin card_ready <= 1; state <= st_finish; end
                        else fail_proc(8'h07);
                    17: if (error_code == 0 && response_r1 == 0) begin
                            replay_index <= 0; state <= st_replay;
                        end else if (error_code != 0) state <= st_finish;
                        else fail_proc(8'h13);
                    default: fail_proc(8'h0f);
                endcase
                st_token: if (!byte_busy) begin
                    byte_tx <= 8'hff; byte_start <= 1; state <= st_token_wait;
                end
                st_token_wait: if (byte_done) begin
                    if (byte_rx == 8'hfe) begin data_index <= 0; data_crc <= 0; state <= st_data; end
                    else if (byte_rx == 8'hff) state <= st_token;
                    else fail_proc(8'h14);
                end
                st_data: if (!byte_busy) begin
                    byte_tx <= 8'hff; byte_start <= 1; state <= st_data_wait;
                end
                st_data_wait: if (byte_done) begin
                    data_crc <= crc16_next(data_crc, byte_rx);
                    if (data_index == 511) begin crc_phase <= 0; state <= st_crc; end
                    else begin data_index <= data_index+1'b1; state <= st_data; end
                end
                st_crc: if (!byte_busy) begin
                    byte_tx <= 8'hff; byte_start <= 1; state <= st_crc_wait;
                end
                st_crc_wait: if (byte_done) begin
                    if (!crc_phase) begin crc_high <= byte_rx; crc_phase <= 1; state <= st_crc; end
                    else begin
                        if ({crc_high, byte_rx} != data_crc) begin
                            if (sector_retry_count < max_sector_retries) begin
                                sector_retry_count <= sector_retry_count+1'b1;
                                error_code <= 0;
                                command_begin(17, high_capacity ? sector_lba : sector_lba << 9, 0);
                            end else begin
                                error_code <= 8'h15;
                                cs_val <= 1; state <= st_trail;
                            end
                        end else begin
                            cs_val <= 1; state <= st_trail;
                        end
                    end
                end
                st_replay: begin
                    sector_valid <= 1;
                    sector_index <= replay_index;
                    if (replay_index == 511) state <= st_finish;
                    else replay_index <= replay_index+1'b1;
                end
                st_finish: begin
                    if (reading_flag) sector_done <= 1; else init_done <= 1;
                    state <= st_idle;
                end
                default: fail_proc(8'h0f);
            endcase
            if (state != st_idle && state != st_finish && state != st_replay &&
                timeout_tick >= (reading_flag ? clk_freq_hz/4 : clk_freq_hz))
                fail_proc(reading_flag ? 8'h16 : 8'h08);
        end
    end
endmodule
