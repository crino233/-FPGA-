`timescale 1ns/1ps
module photo_audio #(
    parameter integer note_samples = 12000,
    parameter integer cue_samples = 4800,
    parameter integer image_count = 4,
    parameter integer index_bits = image_count > 1 ? $clog2(image_count) : 1,
    parameter integer scene_audio = 0
) (
    input wire mem_clk, input wire mem_rst_n,
    input wire pix_clk, input wire pix_rst_n,
    input wire source_enable, input wire frame_commit, input wire music_enable,
    input wire [1:0] audio_scene, input wire [2:0] music_volume,
    input wire [index_bits-1:0] active_index,
    input wire frame_sync, input wire video_de, input wire video_visible,
    input wire underflow_flag,
    output wire audio_valid, output wire [23:0] audio_left_data,
    output wire [23:0] audio_right_data,
    output wire acr_valid, output wire [19:0] acr_cts, output wire [19:0] acr_n,
    output wire error_flag
);
    reg request_flag, ack_flag, sent_flag, source_error;
    reg [index_bits-1:0] held_index;
    reg [1:0] held_scene;
    (* async_reg = "true" *) reg [1:0] ack_sync, request_sync, enable_sync, error_sync, music_sync;
    (* async_reg = "true" *) reg [index_bits-1:0] index_meta, index_sync;
    (* async_reg = "true" *) reg [1:0] scene_meta, scene_sync;
    wire music_enable_pix;
    wire [2:0] music_volume_pix;

    generate if (scene_audio) begin: config_proc
        wire [3:0] live_data={music_enable,music_volume};
        reg [3:0] held_data, active_data;
        reg request_flag, ack_flag, sent_flag;
        (* async_reg = "true" *) reg [1:0] request_sync, ack_sync;
        always @(posedge mem_clk or negedge mem_rst_n) begin
            if (!mem_rst_n) begin
                held_data<=4'b1100; request_flag<=0; sent_flag<=0; ack_sync<=0;
            end else begin
                ack_sync<={ack_sync[0],ack_flag};
                if (request_flag==ack_sync[1] && (!sent_flag || live_data!=held_data)) begin
                    held_data<=live_data; request_flag<=!request_flag; sent_flag<=1;
                end
            end
        end
        always @(posedge pix_clk or negedge pix_rst_n) begin
            if (!pix_rst_n) begin active_data<=4'b1100; request_sync<=0; ack_flag<=0; end
            else begin
                request_sync<={request_sync[0],request_flag};
                if (request_sync[1]!=ack_flag) begin
                    active_data<=held_data; ack_flag<=request_sync[1];
                end
            end
        end
        assign music_enable_pix=active_data[3];
        assign music_volume_pix=active_data[2:0];
    end else begin: legacy_config_proc
        assign music_enable_pix=music_sync[1];
        assign music_volume_pix=3'd4;
    end endgenerate
    wire transfer_busy = request_flag != ack_sync[1];
    always @(posedge mem_clk or negedge mem_rst_n) begin
        if (!mem_rst_n) begin
            ack_sync <= 0; request_flag <= 0; sent_flag <= 0;
            held_index <= 0; held_scene <= 0; source_error <= 0;
        end else begin
            ack_sync <= {ack_sync[0],ack_flag};
            if (source_enable && frame_commit && (!sent_flag || active_index != held_index)) begin
                if (transfer_busy) source_error <= 1;
                else begin
                    held_index <= active_index; held_scene <= scene_audio ? audio_scene : 2'd0;
                    request_flag <= !request_flag; sent_flag <= 1;
                end
            end
        end
    end
    reg frame_sync_old, frame_wait, pending_flag, linked_flag, pixel_error;
    reg image_change;
    reg [1:0] pending_scene, active_scene;
    reg [index_bits-1:0] pending_index, image_index;
    wire incoming_flag = request_sync[1] != ack_flag;
    wire audio_enable = linked_flag && enable_sync[1] && !underflow_flag && !error_flag;
    assign error_flag = error_sync[1] || pixel_error;
    always @(posedge pix_clk or negedge pix_rst_n) begin
        if (!pix_rst_n) begin
            request_sync <= 0; enable_sync <= 0; error_sync <= 0;
            music_sync <= 2'b11;
            index_meta <= 0; index_sync <= 0; scene_meta <= 0; scene_sync <= 0; ack_flag <= 0;
            frame_sync_old <= 0; frame_wait <= 0; pending_flag <= 0;
            linked_flag <= 0; pixel_error <= 0; image_change <= 0;
            pending_index <= 0; image_index <= 0; pending_scene <= 0; active_scene <= 0;
        end else begin
            request_sync <= {request_sync[0],request_flag};
            enable_sync <= {enable_sync[0],source_enable};
            music_sync <= {music_sync[0],music_enable};
            error_sync <= {error_sync[0],source_error};
            index_meta <= held_index; index_sync <= index_meta;
            scene_meta <= held_scene; scene_sync <= scene_meta;
            frame_sync_old <= frame_sync; image_change <= 0;
            if (frame_sync_old && !frame_sync) frame_wait <= 1;
            if (incoming_flag) begin
                pending_index <= index_sync; pending_scene <= scene_sync;
                pending_flag <= 1; ack_flag <= request_sync[1];
                if (pending_flag || (linked_flag && !frame_wait && !(frame_sync_old && !frame_sync)))
                    pixel_error <= 1;
            end
            if (frame_wait && video_de && video_visible && enable_sync[1] && !underflow_flag) begin
                frame_wait <= 0;
                if (pending_flag || incoming_flag) begin
                    image_index <= incoming_flag ? index_sync : pending_index;
                    active_scene <= incoming_flag ? scene_sync : pending_scene;
                    image_change <= !linked_flag || (!scene_audio && image_index !=
                        (incoming_flag ? index_sync : pending_index));
                    linked_flag <= 1; pending_flag <= 0;
                end else if (!linked_flag) pixel_error <= 1;
            end
        end
    end
    wire signed [15:0] sample_data;
    photo_audio_tone #(.note_samples(note_samples),.cue_samples(cue_samples),
        .image_count(image_count),.index_bits(index_bits),.shared_music(scene_audio)) tone_proc (
        .clk(pix_clk),.rst_n(pix_rst_n),.enable(audio_enable),.music_enable(music_enable_pix),
        .audio_scene(active_scene),.music_volume(music_volume_pix),
        .image_change(image_change),.image_index(image_index),
        .sample_valid(audio_valid),.sample_data(sample_data),.cue_active()
    );
    assign audio_left_data = audio_enable ? {sample_data,8'd0} : 24'd0;
    assign audio_right_data = audio_left_data;
    audio_arc_calculate #(.ACR_N(6144)) acr_proc (
        .I_clk(pix_clk),.I_rst(!pix_rst_n),.I_audio_valid(audio_valid),
        .O_acr_valid(acr_valid),.O_acr_cts(acr_cts),.O_acr_n(acr_n)
    );
endmodule
