`timescale 1ns/1ps
module photo_audio_tone #(
    parameter integer test_mode = 0,
    parameter integer note_samples = 12000,
    parameter integer cue_samples = 4800,
    parameter integer image_count = 4,
    parameter integer index_bits = image_count > 1 ? $clog2(image_count) : 1,
    parameter integer shared_music = 0
) (
    input wire clk, input wire rst_n, input wire enable, input wire music_enable,
    input wire image_change, input wire [index_bits-1:0] image_index,
    input wire [1:0] audio_scene, input wire [2:0] music_volume,
    output reg sample_valid, output reg signed [15:0] sample_data,
    output wire cue_active
);
    localparam integer note_bits = note_samples > 1 ? $clog2(note_samples) : 1;
    localparam integer cue_bits = cue_samples > 0 ? $clog2(cue_samples+1) : 1;
    reg [11:0] rate_accumulator;
    reg [19:0] phase;
    reg [note_bits-1:0] note_count;
    reg [cue_bits-1:0] cue_count;
    reg [2:0] note_index;
    localparam [1:0] normal_track=0, exam_track=0, fire_track=0;
    wire [1:0] scene_track = audio_scene==2 ? fire_track :
        audio_scene==1 ? exam_track : normal_track;
    wire [1:0] melody_index = shared_music ? scene_track : image_index;
    wire signed [15:0] raw_sample = sine_sample(phase[19:14]);
    wire sample_tick = rate_accumulator >= 12'd3119;
    wire [19:0] phase_inc = test_mode ? 20'd21845 :
        cue_count != 0 ? 20'd32768 : melody_inc(melody_index,note_index);
    assign cue_active = cue_count != 0;

    function [19:0] melody_inc;
        input [1:0] image;
        input [2:0] note;
        begin
            case ({image,note})
                5'b00_000,5'b00_101,5'b01_001,5'b01_101,
                5'b10_000,5'b11_000,5'b11_011: melody_inc=20'd11431;
                5'b00_001,5'b01_010,5'b01_100,5'b10_010,
                5'b11_010,5'b11_101: melody_inc=20'd14402;
                5'b00_010,5'b00_100,5'b10_011: melody_inc=20'd17127;
                5'b00_011,5'b10_101: melody_inc=20'd22861;
                5'b01_000: melody_inc=20'd9612;
                5'b01_011,5'b10_100: melody_inc=20'd19224;
                5'b10_001: melody_inc=20'd12830;
                5'b11_001,5'b11_100: melody_inc=20'd8563;
                default: melody_inc=20'd11431;
            endcase
        end
    endfunction
    function signed [15:0] volume_proc;
        input signed [15:0] value;
        input [2:0] level;
        reg signed [17:0] expanded_value;
        begin
            expanded_value={{2{value[15]}},value};
            case(level)
                0:volume_proc=16'sd0;
                1:volume_proc=expanded_value>>>2;
                2:volume_proc=expanded_value>>>1;
                3:volume_proc=(expanded_value+(expanded_value<<<1))>>>2;
                default:volume_proc=value;
            endcase
        end
    endfunction
    function signed [15:0] sine_sample;
        input [5:0] index;
        reg [4:0] pos;
        reg signed [15:0] magnitude;
        begin
            pos = index[4] ? 5'd16-{1'b0,index[3:0]} : {1'b0,index[3:0]};
            case (pos)
                0: magnitude=0; 1: magnitude=1176; 2: magnitude=2341;
                3: magnitude=3483; 4: magnitude=4592; 5: magnitude=5657;
                6: magnitude=6667; 7: magnitude=7613; 8: magnitude=8485;
                9: magnitude=9276; 10: magnitude=9978; 11: magnitude=10583;
                12: magnitude=11087; 13: magnitude=11483; 14: magnitude=11769;
                15: magnitude=11942; default: magnitude=12000;
            endcase
            sine_sample = index[5] ? -magnitude : magnitude;
        end
    endfunction
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rate_accumulator <= 0; phase <= 0; note_count <= 0;
            cue_count <= 0; note_index <= 0; sample_valid <= 0; sample_data <= 0;
        end else begin
            rate_accumulator <= sample_tick ? rate_accumulator-12'd3119 : rate_accumulator+12'd6;
            sample_valid <= sample_tick;
            if (sample_tick) begin
                if (!enable) sample_data<=16'sd0;
                else if (cue_count!=0) sample_data<=raw_sample;
                else sample_data<=music_enable ?
                    volume_proc(raw_sample,shared_music ? music_volume : 3'd4) : 16'sd0;
                if (enable) begin
                    phase <= phase+phase_inc;
                    if (cue_count != 0) cue_count <= cue_count-1'b1;
                    else if (note_count == note_samples-1) begin
                        note_count <= 0;
                        note_index <= note_index == 5 ? 0 : note_index+1'b1;
                    end else note_count <= note_count+1'b1;
                end else begin
                    phase <= 0; cue_count <= 0; note_count <= 0; note_index <= 0;
                end
            end
            if (image_change && !test_mode) begin
                cue_count <= cue_samples; note_count <= 0; note_index <= 0;
            end
        end
    end
endmodule
