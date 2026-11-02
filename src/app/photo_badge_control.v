`timescale 1ns/1ps
module photo_badge_control #(
    parameter integer pause_timeout_ms = 10000,
    parameter integer menu_timeout_ms = 5000,
    parameter integer auto_period_ms = 5000
) (
    input wire clk, input wire rst_n, input wire enable, input wire tick_1ms,
    input wire [2:0] short_event, input wire [2:0] long_event,
    input wire key1_short_event, output reg resolution_notice,
    input wire exam_request, input wire fire_request, input wire music_mute,
    input wire player_busy, input wire frame_commit, input wire [3:0] active_index,
    input wire exam_done,
    input wire config_apply, input wire [25:0] config_data,
    output reg player_next_down, output reg player_prev_down, output reg player_auto_step,
    output wire auto_mode, output reg auto_notice, output reg manual_notice, output reg consume_event, output wire temporary_pause,
    output reg [1:0] page_group, output reg page_change,
    output wire [3:0] page_return_index,
    output wire page_return_valid,
    output reg page_select_valid, output reg [3:0] page_select_index,
    output reg menu_active, output reg [2:0] menu_item,
    output reg [1:0] menu_adjust,
    output reg [2:0] music_volume, output reg [2:0] brightness_level,
    output reg [1:0] eye_mode, output reg [1:0] transition_mode,
    output reg subtitle_enable, output reg [2:0] subtitle_speed, output reg [2:0] subtitle_alpha,
    output reg [15:0] slideshow_ms,
    output reg [4:0] slideshow_seconds,
    output reg exam_start_toggle, output reg exam_duration_step, output reg exam_reset,
    output reg exam_pause, output reg exam_finish,
    output reg exam_started, output reg exam_running, output reg exam_finished,
    output reg [2:0] exam_duration_index,
    output wire music_enable, output wire [1:0] scene_mode
);
    localparam integer pause_bits = pause_timeout_ms > 1 ? $clog2(pause_timeout_ms) : 1;
    localparam integer menu_bits = menu_timeout_ms > 1 ? $clog2(menu_timeout_ms) : 1;
    localparam [1:0] page_notice=0, page_culture=1, page_timetable=2;
    reg [pause_bits-1:0] pause_tick;
    reg [menu_bits-1:0] menu_tick;
    reg [15:0] auto_tick;
    reg [1:0] saved_pause, saved_image_valid;
    reg [3:0] saved_image [0:1];
    reg [1:0] return_group, scene_old;
    reg exam_request_old;
    reg displayed_once;
    reg [3:0] displayed_index;
    reg config_user_changed;
    wire [15:0] restore_seconds = {11'd0,config_data[10:6]};
    wire [2:0] exam_event = short_event | long_event;
    wire scene_changed = scene_mode != scene_old;
    wire ordinary_page = page_group != page_timetable;
    wire image_changed = frame_commit && (!displayed_once || active_index != displayed_index);
    wire config_user_event = enable && !scene_changed && !consume_event &&
        ((scene_mode==0 && menu_active && !key1_short_event && !short_event[0] && (short_event[1] || short_event[2])) ||
         (scene_mode==1 && !exam_started && exam_event[1] && !exam_event[0] && !exam_event[2]));
    assign scene_mode = fire_request ? 2'd2 : exam_request ? 2'd1 : 2'd0;
    assign temporary_pause = ordinary_page && saved_pause[page_group[0]];
    assign auto_mode = enable && scene_mode==0 && !menu_active && ordinary_page && !temporary_pause;
    assign music_enable = !music_mute;
    assign page_return_index = saved_image[page_group[0]];
    assign page_return_valid = ordinary_page && saved_image_valid[page_group[0]];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            player_next_down<=0; player_prev_down<=0; player_auto_step<=0;
            consume_event<=0;auto_notice<=0;manual_notice<=0;resolution_notice<=0; page_change<=0; page_select_valid<=0; page_select_index<=0; menu_adjust<=0;
            saved_pause<=0; saved_image_valid<=0; saved_image[0]<=0; saved_image[1]<=0;
            page_group<=page_notice; return_group<=page_notice;
            menu_active<=0; menu_item<=0; music_volume<=4; brightness_level<=4;
            eye_mode<=0;transition_mode<=0;subtitle_enable<=0;subtitle_speed<=2;subtitle_alpha<=1;
            slideshow_ms<=auto_period_ms; slideshow_seconds<=auto_period_ms/1000;
            pause_tick<=0; menu_tick<=0; auto_tick<=0;
            scene_old<=0; exam_request_old<=0;
            displayed_once<=0; displayed_index<=0;
            config_user_changed<=0;
            exam_start_toggle<=0; exam_duration_step<=0; exam_reset<=0; exam_pause<=0; exam_finish<=0;
            exam_started<=0; exam_running<=0; exam_finished<=0; exam_duration_index<=0;
        end else begin
            player_next_down<=0; player_prev_down<=0; player_auto_step<=0;
            consume_event<=0;auto_notice<=0;manual_notice<=0;resolution_notice<=0; page_change<=0; page_select_valid<=0; menu_adjust<=0;
            exam_start_toggle<=0; exam_duration_step<=0; exam_reset<=0; exam_pause<=0; exam_finish<=0;
            scene_old<=scene_mode; exam_request_old<=exam_request;
            if (frame_commit) begin displayed_once<=1; displayed_index<=active_index; end
            if (config_user_event) config_user_changed<=1;

            if (!exam_request) begin
                if (exam_request_old) exam_reset<=1;
                exam_started<=0; exam_running<=0; exam_finished<=0;
            end else if (!exam_request_old) begin
                exam_started<=0; exam_running<=0; exam_finished<=0; exam_reset<=1;
            end else if (fire_request) begin
                if (exam_running) exam_pause<=1;
                exam_running<=0;
            end else if (exam_done && exam_started && !exam_finished) begin
                exam_running<=0; exam_finished<=1; exam_finish<=1;
            end else if (enable && !scene_changed && !consume_event) begin
                if (exam_event[2]) begin
                    exam_reset<=1; exam_started<=0; exam_running<=0; exam_finished<=0;
                end else if (exam_event[0] && !exam_finished) begin
                    exam_start_toggle<=1; exam_started<=1; exam_running<=!exam_running;
                end else if (exam_event[1] && !exam_started) begin
                    exam_duration_step<=1;
                    exam_duration_index<=exam_duration_index==6 ? 0 : exam_duration_index+1'b1;
                end
            end

            if (!enable) begin
                saved_pause<=0; saved_image_valid<=0; page_group<=page_notice; return_group<=page_notice;
                menu_active<=0; pause_tick<=0; menu_tick<=0; auto_tick<=0;
                displayed_once<=0;
            end else if (scene_changed) begin
                menu_active<=0; menu_tick<=0; pause_tick<=0; auto_tick<=0; consume_event<=1;
            end else if (scene_mode!=0 || consume_event) begin
                auto_tick<=0;
            end else if (menu_active) begin
                if (key1_short_event || short_event[0] || short_event[1] || short_event[2]) begin
                    menu_tick<=0;
                    if (key1_short_event) menu_item<=menu_item==0 ? 7 : menu_item-1'b1;
                    else if (short_event[0]) menu_item<=menu_item==7 ? 0 : menu_item+1'b1;
                    else begin
                        menu_adjust<=short_event[1] ? 1 : 2;
                        case (menu_item)
                            0: if (short_event[1]) begin if (music_volume>0) music_volume<=music_volume-1'b1; end
                               else if (music_volume<4) music_volume<=music_volume+1'b1;
                            1: if (short_event[1]) begin if (brightness_level>0) brightness_level<=brightness_level-1'b1; end
                               else if (brightness_level<4) brightness_level<=brightness_level+1'b1;
                            2: if (short_event[1]) begin if (eye_mode>0) eye_mode<=eye_mode-1'b1; end
                               else if (eye_mode<2) eye_mode<=eye_mode+1'b1;
                            3: if (short_event[1]) begin
                                   if (slideshow_ms>1000) begin
                                       slideshow_ms<=slideshow_ms-1000;
                                       slideshow_seconds<=slideshow_seconds-1'b1;
                                   end
                               end else if (slideshow_ms<30000) begin
                                   slideshow_ms<=slideshow_ms+1000;
                                   slideshow_seconds<=slideshow_seconds+1'b1;
                               end
                            4: if (short_event[1]) begin
                                   if (transition_mode>0) transition_mode<=transition_mode-1'b1;
                               end else if (transition_mode<2) transition_mode<=transition_mode+1'b1;
                            5: subtitle_enable<=!short_event[1];
                            6: if(short_event[1])begin if(subtitle_speed>0)subtitle_speed<=subtitle_speed-1'b1;end
                               else if(subtitle_speed<4)subtitle_speed<=subtitle_speed+1'b1;
                            7: if(short_event[1])begin if(subtitle_alpha>0)subtitle_alpha<=subtitle_alpha-1'b1;end
                               else if(subtitle_alpha<4)subtitle_alpha<=subtitle_alpha+1'b1;
                        endcase
                    end
                end else if (tick_1ms) begin
                    if (menu_tick==menu_timeout_ms-1) begin
                        menu_active<=0; menu_tick<=0; pause_tick<=0; auto_tick<=0; consume_event<=1;
                    end else menu_tick<=menu_tick+1'b1;
                end
            end else if (long_event[2]) begin
                menu_active<=1; menu_item<=0; menu_tick<=0; consume_event<=1;
            end else if (long_event[0] || long_event[1]) begin
                if (ordinary_page) begin
                    saved_image[page_group[0]]<=active_index;
                    saved_image_valid[page_group[0]]<=1;
                end
                if (long_event[0]) begin
                    if ((ordinary_page ? page_group : return_group)==page_notice) begin
                        page_group <= page_culture;
                        page_select_valid<=saved_image_valid[page_culture[0]];
                        page_select_index<=saved_image[page_culture[0]];
                    end else begin
                        page_group <= page_notice;
                        page_select_valid<=saved_image_valid[page_notice[0]];
                        page_select_index<=saved_image[page_notice[0]];
                    end
                end else if (ordinary_page) begin
                    return_group<=page_group; page_group<=page_timetable;
                    page_select_valid<=1; page_select_index<=0;
                end else begin
                    page_group<=return_group;
                    page_select_valid<=saved_image_valid[return_group[0]];
                    page_select_index<=saved_image[return_group[0]];
                end
                pause_tick<=0; auto_tick<=0; page_change<=1; consume_event<=1;
            end else if (ordinary_page) begin
                if (short_event[0] || short_event[1]) begin
                    manual_notice<=1;
                    player_prev_down<=short_event[0];
                    player_next_down<=!short_event[0] && short_event[1];
                    saved_pause[page_group[0]]<=1; pause_tick<=0; auto_tick<=0;
                end else if (short_event[2]) begin
                    if(saved_pause[page_group[0]])auto_notice<=1;
                    else manual_notice<=1;
                    saved_pause[page_group[0]]<=!saved_pause[page_group[0]];
                    pause_tick<=0; auto_tick<=0;
                end else if (tick_1ms && temporary_pause) begin
                    if (pause_tick==pause_timeout_ms-1) begin
                        auto_notice<=1;
                        saved_pause[page_group[0]]<=0; pause_tick<=0; auto_tick<=0;
                    end else pause_tick<=pause_tick+1'b1;
                end else if (player_busy || image_changed) auto_tick<=0;
                else if (tick_1ms) begin
                    if (auto_tick==slideshow_ms-1) begin player_auto_step<=1; auto_tick<=0; end
                    else auto_tick<=auto_tick+1'b1;
                end
            end
            if(enable && scene_mode==0 && !scene_changed && !consume_event && !menu_active &&
                !long_event[2] && !long_event[1] && !long_event[0] && key1_short_event)
                resolution_notice<=1;
            if (config_apply && !config_user_changed && !config_user_event && !exam_started &&
                !(exam_request && |exam_event) && config_data[2:0]<=4 && config_data[5:3]<=4 &&
                config_data[10:6]>=1 && config_data[10:6]<=30 && config_data[13:11]<=6 &&
                config_data[15:14]<=2 && config_data[18:17]<=2 && config_data[22:20]<=4 && config_data[25:23]<=4) begin
                music_volume<=config_data[2:0]; brightness_level<=config_data[5:3];
                slideshow_seconds<=config_data[10:6];
                slideshow_ms<=(restore_seconds<<10)-(restore_seconds<<4)-(restore_seconds<<3);
                exam_duration_index<=config_data[13:11]; exam_reset<=1; auto_tick<=0;
                eye_mode<=config_data[15:14];
                transition_mode<=config_data[18:17];
                subtitle_enable<=config_data[19];subtitle_speed<=config_data[22:20];subtitle_alpha<=config_data[25:23];
            end
        end
    end
endmodule
