`timescale 1ns/1ps
module photo_key_input #(
    parameter integer clk_freq_hz = 125000000,
    parameter integer debounce_ms = 20,
    parameter integer long_press_ms = 1000
) (
    input wire clk, input wire rst_n, input wire enable,
    input wire key1_n, input wire key2_n, input wire timer_en,
    output reg tick_1ms, output reg next_down,
    output reg auto_down, output reg prev_down
);
    localparam integer ms_cycles = clk_freq_hz / 1000;
    localparam integer ms_bits = ms_cycles > 1 ? $clog2(ms_cycles) : 1;
    localparam integer debounce_bits = debounce_ms > 1 ? $clog2(debounce_ms) : 1;
    localparam integer hold_bits = long_press_ms > 1 ? $clog2(long_press_ms) : 1;
    reg [1:0] key_meta, key_sync, key_stable, key_armed;
    reg [ms_bits-1:0] ms_tick;
    reg [debounce_bits-1:0] key1_tick, key2_tick;
    reg [hold_bits-1:0] hold_tick;
    reg long_flag;
    wire work_flag = enable && (timer_en || key_sync != key_stable ||
                                  (key_armed[1] && !key_stable[1] && !long_flag));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin key_meta <= 2'b11; key_sync <= 2'b11; end
        else begin key_meta <= {key2_n,key1_n}; key_sync <= key_meta; end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin ms_tick <= 0; tick_1ms <= 0; end
        else begin
            tick_1ms <= 0;
            if (!work_flag) ms_tick <= 0;
            else if (ms_tick == ms_cycles-1) begin
                ms_tick <= 0; tick_1ms <= 1;
            end else ms_tick <= ms_tick+1'b1;
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_stable <= 0; key_armed <= 0;
            key1_tick <= 0; key2_tick <= 0; hold_tick <= 0; long_flag <= 0;
            next_down <= 0; auto_down <= 0; prev_down <= 0;
        end else begin
            next_down <= 0; auto_down <= 0; prev_down <= 0;
            if (!enable) begin
                key_stable <= 0; key_armed <= 0;
                key1_tick <= 0; key2_tick <= 0; hold_tick <= 0; long_flag <= 0;
            end else begin
                if (key_stable[1] || !key_armed[1]) hold_tick <= 0;
                else if (tick_1ms && !key_sync[1] && !long_flag) begin
                    if (hold_tick == long_press_ms-1) begin
                        prev_down <= 1; long_flag <= 1;
                    end else hold_tick <= hold_tick+1'b1;
                end
                if (key_sync[0] == key_stable[0]) key1_tick <= 0;
                else if (tick_1ms) begin
                    if (key1_tick == debounce_ms-1) begin
                        key_stable[0] <= key_sync[0]; key1_tick <= 0;
                        if (key_sync[0]) key_armed[0] <= 1;
                        else if (key_armed[0]) next_down <= 1;
                    end else key1_tick <= key1_tick+1'b1;
                end
                if (key_sync[1] == key_stable[1]) key2_tick <= 0;
                else if (tick_1ms) begin
                    if (key2_tick == debounce_ms-1) begin
                        key_stable[1] <= key_sync[1]; key2_tick <= 0;
                        if (key_sync[1]) begin
                            key_armed[1] <= 1; hold_tick <= 0; long_flag <= 0;
                            if (key_armed[1] && !long_flag) auto_down <= 1;
                        end
                    end else key2_tick <= key2_tick+1'b1;
                end
            end
        end
    end
endmodule
