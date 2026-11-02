`timescale 1ns/1ps
module photo_badge_input #(
    parameter integer clk_freq_hz = 125000000,
    parameter integer debounce_ms = 20,
    parameter integer long_press_ms = 1000
) (
    input wire clk, input wire rst_n, input wire enable, input wire consume,
    input wire key1_n,
    input wire key2_n, input wire key3_n, input wire key4_n,
    input wire sw1, input wire sw3, input wire sw4,
    output reg tick_1ms,
    output reg key1_short_event,
    output wire [2:0] short_event, output wire [2:0] long_event,
    output wire music_mute, output wire exam_request, output wire fire_request
);
    localparam integer ms_cycles = clk_freq_hz / 1000;
    localparam integer ms_bits = ms_cycles > 1 ? $clog2(ms_cycles) : 1;
    localparam integer debounce_bits = debounce_ms > 1 ? $clog2(debounce_ms) : 1;
    localparam integer hold_bits = long_press_ms > 1 ? $clog2(long_press_ms) : 1;
    reg [ms_bits-1:0] ms_tick;
    (* async_reg = "true" *) reg key1_meta,key1_sync;
    (* async_reg = "true" *) reg [2:0] key_meta, key_sync, switch_meta, switch_sync;
    reg [2:0] sync_ready;
    wire [2:0] switch_request;
    reg key1_candidate,key1_stable,key1_known,key1_armed,key1_long_fired;
    reg [debounce_bits-1:0] key1_tick;
    reg [hold_bits-1:0] key1_hold_tick;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key1_meta<=1;key1_sync<=1;
            key_meta <= 3'b111; key_sync <= 3'b111;
            switch_meta <= 0; switch_sync <= 0; sync_ready <= 0;
            ms_tick <= 0; tick_1ms <= 0;key1_short_event<=0;
            key1_candidate<=1;key1_stable<=1;key1_known<=0;key1_armed<=0;
            key1_long_fired<=0;key1_tick<=0;key1_hold_tick<=0;
        end else begin
            key1_meta<=key1_n;key1_sync<=key1_meta;
            key_meta <= {key4_n,key3_n,key2_n}; key_sync <= key_meta;
            switch_meta <= {sw4,sw3,sw1}; switch_sync <= switch_meta;
            sync_ready <= {sync_ready[1:0],1'b1};
            key1_short_event<=0;
            tick_1ms <= 0;
            if (ms_tick == ms_cycles-1) begin ms_tick <= 0; tick_1ms <= 1; end
            else ms_tick <= ms_tick+1'b1;
            if(!enable || consume || !sync_ready[2])begin
                key1_candidate<=key1_sync;key1_stable<=1;key1_known<=0;key1_armed<=0;
                key1_long_fired<=0;key1_tick<=0;key1_hold_tick<=0;
            end else if(tick_1ms)begin
                if(key1_sync!=key1_candidate)begin
                    key1_candidate<=key1_sync;key1_tick<=0;
                end else if(key1_tick==debounce_ms-1)begin
                    key1_stable<=key1_candidate;key1_known<=1;
                    if(!key1_known || key1_stable!=key1_candidate)begin
                        key1_hold_tick<=0;
                        if(key1_candidate)begin
                            if(key1_known && key1_armed && !key1_long_fired)
                                key1_short_event<=1;
                            key1_armed<=1;key1_long_fired<=0;
                        end
                    end
                end else key1_tick<=key1_tick+1'b1;
                if(key1_known && !key1_stable && !key1_sync && key1_armed && !key1_long_fired)begin
                    if(key1_hold_tick==long_press_ms-1)key1_long_fired<=1;
                    else key1_hold_tick<=key1_hold_tick+1'b1;
                end
            end
        end
    end

    genvar i;
    generate for (i=0;i<3;i=i+1) begin: input_proc
        reg key_candidate, key_stable, key_known, key_armed, long_fired;
        reg [debounce_bits-1:0] key_tick;
        reg [hold_bits-1:0] hold_tick;
        reg short_down, long_down;
        reg switch_candidate, switch_stable, switch_known, switch_armed;
        reg [debounce_bits-1:0] switch_tick;
        assign short_event[i] = short_down;
        assign long_event[i] = long_down;
        assign switch_request[i] = switch_known && switch_stable && (i==0 || switch_armed);

        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                key_candidate <= 1; key_stable <= 1; key_known <= 0;
                key_armed <= 0; long_fired <= 0;
                key_tick <= 0; hold_tick <= 0; short_down <= 0; long_down <= 0;
            end else begin
                short_down <= 0; long_down <= 0;
                if (!enable || consume || !sync_ready[2]) begin
                    key_candidate <= key_sync[i]; key_stable <= 1; key_known <= 0;
                    key_armed <= 0; long_fired <= 0; key_tick <= 0; hold_tick <= 0;
                end else if (tick_1ms) begin
                    if (key_sync[i] != key_candidate) begin
                        key_candidate <= key_sync[i]; key_tick <= 0;
                    end else if (key_tick == debounce_ms-1) begin
                        key_stable <= key_candidate;
                        key_known <= 1;
                        if (!key_known || key_stable != key_candidate) begin
                            hold_tick <= 0;
                            if (key_candidate) begin
                                if (key_known && key_armed && !long_fired) short_down <= 1;
                                key_armed <= 1; long_fired <= 0;
                            end
                        end
                    end else key_tick <= key_tick+1'b1;
                    if (key_known && !key_stable && !key_sync[i] && key_armed && !long_fired) begin
                        if (hold_tick == long_press_ms-1) begin long_down <= 1; long_fired <= 1; end
                        else hold_tick <= hold_tick+1'b1;
                    end
                end
            end
        end

        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                switch_candidate <= 0; switch_stable <= 0;
                switch_known <= 0; switch_armed <= 0; switch_tick <= 0;
            end else if (!sync_ready[2]) begin
                switch_candidate <= switch_sync[i]; switch_tick <= 0;
            end else if (tick_1ms) begin
                if (switch_sync[i] != switch_candidate) begin
                    switch_candidate <= switch_sync[i]; switch_tick <= 0;
                end else if (switch_tick == debounce_ms-1) begin
                    switch_stable <= switch_candidate; switch_known <= 1;
                    if (!switch_candidate) switch_armed <= 1;
                end else switch_tick <= switch_tick+1'b1;
            end
        end
    end endgenerate
    assign music_mute = switch_request[0];
    assign exam_request = switch_request[1];
    assign fire_request = switch_request[2];
endmodule
