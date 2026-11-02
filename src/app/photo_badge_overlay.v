module photo_badge_overlay #(parameter integer interaction_osd=0) (
    input wire mem_clk, input wire mem_rst_n,
    input wire clk, input wire rst_n, input wire vs, input wire de,
    input wire [23:0] rgb_in,
    input wire frame_sync, input wire frame_commit, input wire [3:0] active_index,
    input wire [11:0] active_source_width,input wire [11:0] active_source_height,
    input wire video_visible, input wire underflow_flag,
    input wire menu_active, input wire [2:0] menu_item,
    input wire music_mute,input wire auto_notice,input wire manual_notice,input wire resolution_notice,
    input wire tick_1ms,input wire manual_pause,
    input wire [2:0] music_volume, input wire [2:0] brightness_level,
    input wire [1:0] eye_mode,
    input wire [1:0] transition_mode, input wire [7:0] transition_alpha,
    input wire transition_wipe_active, input wire [4:0] transition_wipe_ramp,
    input wire [4:0] slideshow_seconds, input wire [1:0] scene_mode,
    input wire exam_started, input wire exam_running, input wire exam_finished,
    input wire [2:0] exam_duration_index,
    input wire [7:0] exam_minutes, input wire [5:0] exam_second,
    input wire subtitle_enable, input wire subtitle_ready,
    input wire [2:0] subtitle_speed, input wire [2:0] subtitle_alpha,
    input wire [4:0] subtitle_notice_length, input wire [4:0] subtitle_teacher_length,
    input wire subtitle_mem_en, input wire subtitle_mem_write_en, input wire [10:0] subtitle_mem_addr,
    input wire [15:0] subtitle_mem_write_data, output wire [15:0] subtitle_mem_read_data,
    output reg [23:0] rgb_out, output reg overlay_active,
    output wire frame_start_out, output reg [3:0] visible_index_out,
    output reg visible_valid_out, output wire incoming_valid_out,
    output wire [3:0] incoming_index_out, output wire scene_visible_out,
    output reg visible_frame_pulse_out,
    output wire [11:0] visible_source_width_out,output wire [11:0] visible_source_height_out
);
    wire [49:0] config_live={interaction_osd ? music_mute : 1'b0,subtitle_alpha,subtitle_speed,subtitle_enable,transition_mode,exam_duration_index,eye_mode,1'b0,menu_active,menu_item,
        music_volume,brightness_level,slideshow_seconds,scene_mode,
        exam_started,exam_running,exam_finished,exam_minutes,exam_second};
    reg [49:0] config_hold;
    reg notice_toggle, manual_toggle,resolution_toggle;
    (* async_reg="true" *) reg [1:0] notice_sync;
    (* async_reg="true" *) reg [1:0] manual_sync;
    (* async_reg="true" *) reg [1:0] resolution_sync;
    (* async_reg="true" *) reg [1:0] pause_sync;
    reg notice_seen,mute_frame,manual_seen,resolution_seen;
    localparam [10:0] notice_duration_ms=2000;
    reg [10:0] resolution_ms;
    reg [5:0] notice_frames;
    reg [6:0] mute_frames,manual_frames;
    reg config_request, config_ack, config_sent;
    reg [27:0] image_hold;
    reg image_request, image_ack, image_sent;
    reg millisecond_toggle;
    (* async_reg="true" *) reg [1:0] millisecond_sync,normal_sync;
    reg millisecond_seen;
    reg [15:0] resolution_width_frame,resolution_height_frame;
    (* async_reg = "true" *) reg [1:0] config_ack_sync, config_request_sync;
    (* async_reg = "true" *) reg [1:0] image_ack_sync, image_request_sync;

    always @(posedge mem_clk or negedge mem_rst_n) begin
        if (!mem_rst_n) begin
            config_hold<=0; config_request<=0; config_sent<=0; config_ack_sync<=0;
            image_hold<=0; image_request<=0; image_sent<=0; image_ack_sync<=0;
            notice_toggle<=0;manual_toggle<=0;resolution_toggle<=0;millisecond_toggle<=0;
        end else begin
            config_ack_sync<={config_ack_sync[0],config_ack};
            image_ack_sync<={image_ack_sync[0],image_ack};
            if(interaction_osd && auto_notice)notice_toggle<=!notice_toggle;
            if(interaction_osd && manual_notice)manual_toggle<=!manual_toggle;
            if(interaction_osd && resolution_notice)resolution_toggle<=!resolution_toggle;
            if(tick_1ms)millisecond_toggle<=!millisecond_toggle;
            if (config_request==config_ack_sync[1] && (!config_sent || config_live!=config_hold)) begin
                config_hold<=config_live; config_request<=!config_request; config_sent<=1;
            end
            if (frame_commit && image_request==image_ack_sync[1] &&
                (!image_sent || active_index!=image_hold[3:0])) begin
                image_hold<={active_source_height,active_source_width,active_index};
                image_request<=!image_request; image_sent<=1;
            end
        end
    end

    reg [9:0] pixel_x;
    reg [8:0] pixel_y;
    reg de_old, vs_old, frame_sync_old, frame_window;
    reg visible_frame_seen,visible_frame_bad;
    reg [11:0] visible_source_width_pix,visible_source_height_pix;
    assign visible_source_width_out=visible_source_width_pix;
    assign visible_source_height_out=visible_source_height_pix;
    reg menu_frame, exam_started_frame, exam_running_frame, exam_finished_frame;
    reg [2:0] menu_item_frame;
    reg [1:0] scene_frame, eye_frame;
    reg [2:0] subtitle_speed_frame,subtitle_alpha_frame;
    reg [1:0] transition_mode_frame;
    reg subtitle_frame;
    (* async_reg="true" *) reg [1:0] subtitle_ready_sync;
    reg subtitle_loaded;
    reg [4:0] notice_length_frame, teacher_length_frame;
    reg [9:0] notice_scroll, teacher_scroll;
    reg [2:0] notice_div, teacher_div;
    wire [2:0] subtitle_div_limit=subtitle_speed_frame==0 ? 3'd7 : subtitle_speed_frame==1 ? 3'd3 : subtitle_speed_frame==2 ? 3'd1 : 3'd0;
    wire [1:0] subtitle_step=subtitle_speed_frame==4 ? 2'd2 : 2'd1;
    function [9:0] scroll_next;
        input [9:0] value;
        input [4:0] length;
        input [1:0] step;
        reg [10:0] next_value,limit;
        begin
            next_value={1'b0,value}+{9'd0,step};limit=11'd608+{2'd0,length,4'd0};
            scroll_next=next_value>=limit ? next_value-limit : next_value;
        end
    endfunction
    reg [2:0] volume_frame, brightness_frame;
    wire sound_box=interaction_osd && mute_frames!=0;
    wire mute_box=sound_box && (mute_frame || volume_frame==0);
    wire unmute_box=sound_box && !mute_box;
    wire auto_box=interaction_osd && notice_frames!=0 && scene_frame==0;
    wire manual_box=interaction_osd && manual_frames!=0 && scene_frame==0;
    wire resolution_box=interaction_osd && resolution_ms!=0 && scene_frame==0 &&
        !menu_frame && normal_sync[1] && visible_valid_out && video_visible && !underflow_flag;
    wire [9:0] resolution_x=sound_box ? 10'd352 : 10'd464;
    wire [8:0] badge_y=menu_frame ? 9'd216 : 9'd16;
    wire [9:0] auto_x=sound_box ? 10'd464 : 10'd576;
    reg [4:0] slideshow_frame;
    reg [11:0] minutes_bcd, minutes_frame;
    reg [7:0] seconds_bcd, seconds_frame, interval_bcd, interval_frame;
    reg [7:0] progress_bcd, progress_frame;
    reg [2:0] decimal_mode;
    reg [7:0] decimal_value;
    reg [11:0] decimal_data;
    reg config_ready,sound_config_seen;
    reg [5:0] blink_tick;
    wire frame_start=vs_old && !vs;
    assign frame_start_out=frame_start;
    assign incoming_valid_out=image_request_sync[1]!=image_ack || visible_valid_out;
    assign incoming_index_out=image_request_sync[1]!=image_ack ? image_hold[3:0] : visible_index_out;
    wire config_pending=config_request_sync[1]!=config_ack;
    wire demo_duration=config_hold[39:37]==3'd6;
    wire [2:0] progress_unit=demo_duration ? 3'd2 : config_hold[39:37]+3'd1;
    wire millisecond_tick=millisecond_sync[1]!=millisecond_seen;
    wire manual_event=manual_sync[1]!=manual_seen;
    wire auto_event=notice_sync[1]!=notice_seen;
    wire resolution_event=resolution_sync[1]!=resolution_seen;
    wire image_visible_change=frame_window && de && video_visible && !underflow_flag &&
        image_request_sync[1]!=image_ack;
    reg resolution_busy,resolution_ready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_x<=0; pixel_y<=0; de_old<=0; vs_old<=1;notice_sync<=0;manual_sync<=0;resolution_sync<=0;pause_sync<=0;
            notice_seen<=0;manual_seen<=0;resolution_seen<=0;resolution_ms<=0;
            mute_frame<=0;notice_frames<=0;mute_frames<=0;manual_frames<=0;
            millisecond_sync<=0;millisecond_seen<=0;normal_sync<=0;
            config_request_sync<=0; config_ack<=0; image_request_sync<=0; image_ack<=0;
            frame_sync_old<=1; frame_window<=0; visible_index_out<=0; visible_valid_out<=0;
            visible_source_width_pix<=0;visible_source_height_pix<=0;
            visible_frame_seen<=0;visible_frame_bad<=0;visible_frame_pulse_out<=0;
            decimal_mode<=0; decimal_value<=0; decimal_data<=0; config_ready<=0;sound_config_seen<=0;
            minutes_bcd<=0; seconds_bcd<=0; interval_bcd<=8'h05;
            menu_frame<=0; menu_item_frame<=0; volume_frame<=4; brightness_frame<=4;
            eye_frame<=0;subtitle_speed_frame<=2;subtitle_alpha_frame<=1;transition_mode_frame<=0;blink_tick<=0;
            subtitle_frame<=0;subtitle_ready_sync<=0;subtitle_loaded<=0;
            notice_length_frame<=0;teacher_length_frame<=0;
            notice_scroll<=0;teacher_scroll<=0;notice_div<=0;teacher_div<=0;
            slideshow_frame<=5; interval_frame<=8'h05; scene_frame<=0; exam_started_frame<=0;
            exam_running_frame<=0; exam_finished_frame<=0; minutes_frame<=0; seconds_frame<=0;
            progress_bcd<=240; progress_frame<=240;
        end else begin
            vs_old<=vs; de_old<=de;
            notice_sync<={notice_sync[0],notice_toggle};
            manual_sync<={manual_sync[0],manual_toggle};
            resolution_sync<={resolution_sync[0],resolution_toggle};
            millisecond_sync<={millisecond_sync[0],millisecond_toggle};
            millisecond_seen<=millisecond_sync[1];
            normal_sync<={normal_sync[0],!menu_active && scene_mode==0};
            pause_sync<={pause_sync[0],interaction_osd ? manual_pause : 1'b0};
            if (!vs) begin pixel_x<=0; pixel_y<=0; end
            else begin
                if (!de) pixel_x<=0;
                else if (pixel_x<639) pixel_x<=pixel_x+1'b1;
                if (de_old && !de && pixel_y<479) pixel_y<=pixel_y+1'b1;
            end
            config_request_sync<={config_request_sync[0],config_request};
            image_request_sync<={image_request_sync[0],image_request};
            subtitle_ready_sync<={subtitle_ready_sync[0],subtitle_ready};
            visible_frame_pulse_out<=0;
            resolution_seen<=resolution_sync[1];
            if(millisecond_tick && resolution_ms!=0)resolution_ms<=resolution_ms-1'b1;
            if(!normal_sync[1] || scene_frame!=0 || menu_frame || image_visible_change || manual_event || auto_event)
                resolution_ms<=0;
            else if(interaction_osd && resolution_ready)resolution_ms<=notice_duration_ms;
            if(manual_event)begin
                manual_seen<=manual_sync[1];manual_frames<=7'd60;notice_frames<=0;
            end
            frame_sync_old<=frame_sync;
            if (frame_sync_old && !frame_sync) frame_window<=1;
            if (frame_start) begin
                if(visible_valid_out && visible_frame_seen && !visible_frame_bad)
                    visible_frame_pulse_out<=1;
                visible_frame_seen<=0;visible_frame_bad<=0;
                if(mute_frames!=0)mute_frames<=mute_frames-1'b1;
                if(manual_frames!=0)manual_frames<=manual_frames-1'b1;
            end
            if(visible_valid_out && de && video_visible && pixel_x==639 && pixel_y==479)
                visible_frame_seen<=1;
            if(de && (!video_visible || underflow_flag))visible_frame_bad<=1;
            if (frame_window && de && video_visible && !underflow_flag) begin
                frame_window<=0;
                if (image_request_sync[1]!=image_ack) begin
                    visible_index_out<=image_hold[3:0];
                    visible_source_width_pix<=image_hold[15:4];
                    visible_source_height_pix<=image_hold[27:16];
                    visible_valid_out<=1; image_ack<=image_request_sync[1];
                end
            end
            if (frame_start) begin
                if(scene_frame!=0 || pause_sync[1])begin notice_frames<=0;notice_seen<=notice_sync[1];end
                else if(notice_sync[1]!=notice_seen)begin notice_frames<=60;notice_seen<=notice_sync[1];end
                else if(notice_frames!=0)notice_frames<=notice_frames-1'b1;
                if(subtitle_ready_sync[1])begin
                    subtitle_loaded<=1;notice_length_frame<=subtitle_notice_length;
                    teacher_length_frame<=subtitle_teacher_length;
                end
                if(!subtitle_frame)begin
                    notice_scroll<=0;teacher_scroll<=0;notice_div<=0;teacher_div<=0;
                end else if(subtitle_loaded && !menu_frame && scene_frame==0 &&
                    visible_valid_out && !underflow_flag)begin
                    if(visible_index_out>=1 && visible_index_out<=3 && notice_length_frame!=0)begin
                        notice_div<=notice_div>=subtitle_div_limit ? 0 : notice_div+1'b1;
                        if(notice_div>=subtitle_div_limit)notice_scroll<=scroll_next(notice_scroll,notice_length_frame,subtitle_step);
                    end else if(visible_index_out>=4 && visible_index_out<=7 && teacher_length_frame!=0)begin
                        teacher_div<=teacher_div>=subtitle_div_limit ? 0 : teacher_div+1'b1;
                        if(teacher_div>=subtitle_div_limit)teacher_scroll<=scroll_next(teacher_scroll,teacher_length_frame,subtitle_step);
                    end
                end
                if (scene_frame==2 || exam_finished_frame)
                    blink_tick<=blink_tick==59 ? 0 : blink_tick+1'b1;
                else blink_tick<=0;
            end

            if(resolution_ready && normal_sync[1] && scene_frame==0 && !menu_frame &&
                !image_visible_change && !manual_event && !auto_event)begin
                notice_frames<=0;manual_frames<=0;
            end
            if (config_pending && !config_ready && decimal_mode==0) begin
                decimal_value<=config_hold[13:6]; decimal_data<=0; decimal_mode<=1;
            end else if (decimal_mode==4) begin
                if (decimal_value>={5'd0,progress_unit} && decimal_data[4:0]<30) begin
                    decimal_value<=decimal_value-{5'd0,progress_unit};
                    decimal_data[4:0]<=decimal_data[4:0]+1'b1;
                end else begin
                    progress_bcd<={decimal_data[4:0],3'd0};
                    decimal_mode<=0; config_ready<=1;
                end
            end else if (decimal_mode!=0) begin
                if (decimal_value>=100) begin
                    decimal_value<=decimal_value-8'd100;
                    decimal_data[11:8]<=decimal_data[11:8]+1'b1;
                end else if (decimal_value>=10) begin
                    decimal_value<=decimal_value-8'd10;
                    decimal_data[7:4]<=decimal_data[7:4]+1'b1;
                end else begin
                    decimal_data<=0;
                    case(decimal_mode)
                        1: begin
                            minutes_bcd<={decimal_data[11:4],decimal_value[3:0]};
                            decimal_value<={2'd0,config_hold[5:0]}; decimal_mode<=2;
                        end
                        2: begin
                            seconds_bcd<={decimal_data[7:4],decimal_value[3:0]};
                            decimal_value<={3'd0,config_hold[23:19]}; decimal_mode<=3;
                        end
                        default: begin
                            interval_bcd<={decimal_data[7:4],decimal_value[3:0]};
                            decimal_value<=demo_duration ?
                                (config_hold[13:6]!=0 ? 8'd60 : {2'd0,config_hold[5:0]}) : config_hold[13:6];
                            decimal_mode<=4;
                        end
                    endcase
                end
            end
            if (frame_start && config_ready) begin
                if((mute_frame || volume_frame==0)!=(config_hold[49] || config_hold[29:27]==0) ||
                    (sound_config_seen && !config_hold[49] && config_hold[29:27]!=0 && volume_frame!=config_hold[29:27]))
                    mute_frames<=7'd90;
                sound_config_seen<=1;
                {eye_frame,menu_frame,menu_item_frame,volume_frame,brightness_frame,
                    slideshow_frame,scene_frame,exam_started_frame,exam_running_frame,exam_finished_frame}
                    <={config_hold[36:35],config_hold[33:14]};
                transition_mode_frame<=config_hold[41:40];
                mute_frame<=config_hold[49];
                subtitle_frame<=config_hold[42];subtitle_speed_frame<=config_hold[45:43];subtitle_alpha_frame<=config_hold[48:46];
                if(subtitle_speed_frame!=config_hold[45:43])begin notice_div<=0;teacher_div<=0;end
                minutes_frame<=minutes_bcd; seconds_frame<=seconds_bcd;
                interval_frame<=interval_bcd; progress_frame<=progress_bcd;
                config_ack<=config_request_sync[1]; config_ready<=0;
            end
        end
    end

    function [7:0] brightness_proc;
        input [7:0] value;
        input [2:0] level;
        reg [9:0] three_value;
        begin
            three_value={2'd0,value}+{1'd0,value,1'b0};
            case(level)
                0:brightness_proc=0;
                1:brightness_proc={2'd0,value[7:2]};
                2:brightness_proc={1'd0,value[7:1]};
                3:brightness_proc=three_value[9:2];
                default:brightness_proc=value;
            endcase
        end
    endfunction
    function [7:0] transition_scale;
        input [7:0] value;
        input [7:0] alpha;
        reg [11:0] low_pair, high_pair, scaled;
        begin
            low_pair=(alpha[4] ? {4'd0,value} : 12'd0)+
                (alpha[5] ? {3'd0,value,1'd0} : 12'd0);
            high_pair=(alpha[6] ? {2'd0,value,2'd0} : 12'd0)+
                (alpha[7] ? {1'd0,value,3'd0} : 12'd0);
            scaled=low_pair+high_pair;
            transition_scale=alpha==8'hff ? value : scaled[11:4];
        end
    endfunction
    wire [9:0] transition_boundary={transition_wipe_ramp,5'b0}+{2'd0,transition_wipe_ramp,3'b0};
    wire [23:0] transition_rgb=transition_wipe_active ?
        (pixel_x<transition_boundary ? rgb_in : 24'd0) :
        {transition_scale(rgb_in[23:16],transition_alpha),
         transition_scale(rgb_in[15:8],transition_alpha),transition_scale(rgb_in[7:0],transition_alpha)};
    wire [7:0] bright_blue=brightness_proc(transition_rgb[7:0],brightness_frame);
    wire [23:0] background_rgb={brightness_proc(transition_rgb[23:16],brightness_frame),
        brightness_proc(transition_rgb[15:8],brightness_frame),
        brightness_proc(bright_blue,eye_frame==1 ? 3'd3 : eye_frame==2 ? 3'd2 : 3'd4)};
    wire scene_visible=visible_valid_out && video_visible && !underflow_flag &&
        ((scene_frame==1 && visible_index_out==8) || (scene_frame==2 && visible_index_out==9));
    assign scene_visible_out=scene_visible;
    wire blink_on=blink_tick<30;
    wire [2:0] window_start=menu_item_frame>2 ? menu_item_frame-3'd2 : 3'd0;
    wire warning_time=minutes_frame<12'h005 || (minutes_frame==12'h005 && seconds_frame==0);
    wire urgent_time=minutes_frame==0 || (minutes_frame==12'h001 && seconds_frame==0);
    wire [23:0] timer_color=exam_finished_frame ? 24'hff8278 :
        exam_running_frame && urgent_time ? 24'hff8278 :
        exam_running_frame && warning_time ? 24'hffbd70 : 24'hf2fbf7;
    wire [23:0] status_color=exam_finished_frame ? (blink_on ? 24'hff8278 : 24'h63342e) :
        !exam_started_frame ? 24'h9ddce4 : !exam_running_frame ? 24'hfff080 :
        urgent_time ? 24'hff8278 : warning_time ? 24'hffbd70 : 24'h7ee2a8;

    reg [3:0] resolution_tick;
    reg [11:0] resolution_width_work,resolution_height_work;
    reg [15:0] resolution_width_work_bcd,resolution_height_work_bcd;
    function [15:0] bcd_shift;
        input [15:0] value;
        input next_bit;
        reg [15:0] adjusted;
        integer i;
        begin
            adjusted=value;
            for(i=0;i<4;i=i+1)
                if(value[i*4 +: 4]>=5)adjusted[i*4 +: 4]=value[i*4 +: 4]+4'd3;
            bcd_shift={adjusted[14:0],next_bit};
        end
    endfunction
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            resolution_busy<=0;resolution_ready<=0;resolution_tick<=0;
            resolution_width_work<=0;resolution_height_work<=0;
            resolution_width_work_bcd<=0;resolution_height_work_bcd<=0;
            resolution_width_frame<=0;resolution_height_frame<=0;
        end else begin
            resolution_ready<=0;
            if(!normal_sync[1] || scene_frame!=0 || menu_frame || image_visible_change || manual_event || auto_event)
                resolution_busy<=0;
            else if(resolution_event && visible_valid_out && video_visible && !underflow_flag &&
                visible_source_width_pix>=64 && visible_source_width_pix<=2048 &&
                visible_source_height_pix>=64 && visible_source_height_pix<=2048)begin
                resolution_width_work<=visible_source_width_pix;resolution_height_work<=visible_source_height_pix;
                resolution_width_work_bcd<=0;resolution_height_work_bcd<=0;
                resolution_tick<=0;resolution_busy<=1;
            end else if(resolution_busy)begin
                resolution_width_work<={resolution_width_work[10:0],1'b0};
                resolution_height_work<={resolution_height_work[10:0],1'b0};
                resolution_width_work_bcd<=bcd_shift(resolution_width_work_bcd,resolution_width_work[11]);
                resolution_height_work_bcd<=bcd_shift(resolution_height_work_bcd,resolution_height_work[11]);
                if(resolution_tick==11)begin
                    resolution_width_frame<=bcd_shift(resolution_width_work_bcd,resolution_width_work[11]);
                    resolution_height_frame<=bcd_shift(resolution_height_work_bcd,resolution_height_work[11]);
                    resolution_ready<=1;resolution_busy<=0;
                end else resolution_tick<=resolution_tick+1'b1;
            end
        end
    end
    wire [2:0] resolution_width_digits=resolution_width_frame[15:12]!=0 ? 3'd4 :
        resolution_width_frame[11:8]!=0 ? 3'd3 : 3'd2;
    wire [2:0] resolution_height_digits=resolution_height_frame[15:12]!=0 ? 3'd4 :
        resolution_height_frame[11:8]!=0 ? 3'd3 : 3'd2;
    wire [3:0] resolution_cells={1'b0,resolution_width_digits}+{1'b0,resolution_height_digits}+4'd1;
    wire [9:0] resolution_text_x=resolution_x+10'd80-{3'd0,resolution_cells,3'd0};
    function [3:0] dimension_digit;
        input [15:0] value;
        input [2:0] digits;
        input [3:0] cell_index;
        begin
            case({1'b0,digits}-cell_index)
                4:dimension_digit=value[15:12];
                3:dimension_digit=value[11:8];
                2:dimension_digit=value[7:4];
                default:dimension_digit=value[3:0];
            endcase
        end
    endfunction

    function [8:0] word_glyph;
        input [4:0] word_index;
        input [2:0] index;
        begin
            word_glyph={1'b0,word_index,index};
        end
    endfunction

    function [20:0] text_lookup;
        input [9:0] x;
        input [8:0] y;
        reg [9:0] dx;
        reg [8:0] dy;
        reg [3:0] cell_index, glyph_row, glyph_col;
        reg [2:0] slot, item, level, style;
        reg [8:0] glyph;
        reg hit;
        begin
            dx=0; dy=0; cell_index=0; glyph_row=0; glyph_col=0;
            slot=0; item=0; level=0; style=0; glyph=9'd256; hit=0;
            if (menu_frame) begin
                if (y>=32 && y<48 && x>=384 && x<416) begin
                    dx=x-384; dy=y-32; hit=1;
                    glyph=word_glyph(0,{2'd0,dx[4]});
                end else if (y>=32 && y<48 && x>=560 && x<608) begin
                    dx=x-560; dy=y-32; hit=1; style=2;
                    case(dx[5:4])0:glyph=9'd301+{6'd0,menu_item_frame};
                        1:glyph=312;default:glyph=308;endcase
                end else if ((y>=64 && y<80) || (y>=100 && y<116) || (y>=136 && y<152)) begin
                    if (y<80) begin slot=0;dy=y-64;end
                    else if (y<116) begin slot=1;dy=y-100;end
                    else begin slot=2;dy=y-136;end
                    item=window_start+slot; style=item==menu_item_frame ? 1 : 0;
                    level=item==0 ? volume_frame : item==7 ? subtitle_alpha_frame : brightness_frame;
                    if (x>=384 && x<416) begin
                        dx=x-384; hit=1;
                        glyph=item==7 ? word_glyph(5'd24,{2'd0,dx[4]}) :
                            item==6 ? word_glyph(5'd23,{2'd0,dx[4]}) :
                            item==5 ? word_glyph(5'd21,{2'd0,dx[4]}) :
                            item==4 ? word_glyph(5'd18,{2'd0,dx[4]}) :
                            word_glyph({2'd0,item}+5'd1,{2'd0,dx[4]});
                    end else if (x>=544 && x<608) begin
                        dx=x-544; cell_index={2'd0,dx[5:4]}; hit=1;
                        case(item)
                            0,1,7:case(cell_index)
                                0:glyph=level==4 ? 301 : 256;
                                1:case(level)1:glyph=302;2:glyph=305;3:glyph=307;4:glyph=300;default:glyph=256;endcase
                                2:glyph=(level==1 || level==3) ? 305 : 300;
                                default:glyph=310;
                            endcase
                            2:if(cell_index>=2)glyph=word_glyph(5'd6+{3'd0,eye_frame},{2'd0,dx[4]});
                            3:case(cell_index)1:glyph=300+{5'd0,interval_frame[7:4]};
                                2:glyph=300+{5'd0,interval_frame[3:0]};3:glyph=277;default:glyph=256;endcase
                            4:case(transition_mode_frame)
                                0:if(cell_index==1 || cell_index==2)
                                    glyph=word_glyph(5'd6,cell_index-1'b1);
                                1:glyph=word_glyph(5'd19,cell_index[2:0]);
                                default:glyph=word_glyph(5'd20,cell_index[2:0]);
                            endcase
                            5:if(cell_index>=2)glyph=word_glyph(subtitle_frame ? 5'd22 : 5'd6,{2'd0,dx[4]});
                            6:if(cell_index==2)glyph=9'd301+{6'd0,subtitle_speed_frame};
                        endcase
                    end
                end else if(y>=172 && y<188)begin
                    dy=y-172;style=0;
                    if(x>=408 && x<488)begin
                        dx=x-408;cell_index=dx[7:4];hit=cell_index<5;
                        case(cell_index)
                            0:glyph=9'd331;1:glyph=9'd301;
                            2:glyph=9'd339;3:glyph=9'd340;default:glyph=9'd341;
                        endcase
                    end else if(x>=504 && x<584)begin
                        dx=x-504;cell_index=dx[7:4];hit=cell_index<5;
                        case(cell_index)
                            0:glyph=9'd331;1:glyph=9'd302;
                            2:glyph=9'd342;3:glyph=9'd340;default:glyph=9'd341;
                        endcase
                    end
                    glyph_row=dy[3:0];glyph_col=dx[3:0];
                end else if(y>=188 && y<204)begin
                    dy=y-188;style=0;
                    if(x>=416 && x<480)begin
                        dx=x-416;cell_index=dx[7:4];hit=cell_index<4;
                        case(cell_index)
                            0:glyph=9'd331;1:glyph=9'd303;
                            2:glyph=9'd343;default:glyph=9'd344;
                        endcase
                    end else if(x>=520 && x<584)begin
                        dx=x-520;cell_index=dx[7:4];hit=cell_index<4;
                        case(cell_index)
                            0:glyph=9'd331;1:glyph=9'd304;
                            2:glyph=9'd345;default:glyph=9'd346;
                        endcase
                    end
                    glyph_row=dy[3:0];glyph_col=dx[3:0];
                end
                glyph_row=dy[3:0]; glyph_col=dx[3:0];
            end else if (scene_visible && scene_frame==1) begin
                if (y>=148 && y<180 && x>=256 && x<384) begin
                    dx=x-256; dy=y-148; hit=1; style=3;
                    glyph=word_glyph(11,{1'd0,dx[6:5]});
                    glyph_row=dy[4:1]; glyph_col=dx[4:1];
                end else if (y>=196 && y<260 && x>=224 && x<416) begin
                    dx=x-224; dy=y-196; hit=1; style=5; cell_index={1'd0,dx[7:5]};
                    case(cell_index)
                        0:glyph=minutes_frame[11:8]==0 ? 256 : 300+{5'd0,minutes_frame[11:8]};
                        1:glyph=300+{5'd0,minutes_frame[7:4]};
                        2:glyph=300+{5'd0,minutes_frame[3:0]};
                        3:glyph=311;
                        4:glyph=300+{5'd0,seconds_frame[7:4]};
                        default:glyph=300+{5'd0,seconds_frame[3:0]};
                    endcase
                    glyph_row=dy[5:2]; glyph_col=dx[4:1];
                end else if (y>=280 && y<312) begin
                    if (exam_started_frame && exam_running_frame && !exam_finished_frame) begin
                        dx=x-272; hit=x>=272 && x<368;
                    end else begin dx=x-288; hit=x>=288 && x<352;end
                    dy=y-280; style=4;
                    if(exam_finished_frame)glyph=word_glyph(15,dx[7:5]);
                    else if(!exam_started_frame)glyph=word_glyph(12,dx[7:5]);
                    else if(exam_running_frame)glyph=word_glyph(13,dx[7:5]);
                    else glyph=word_glyph(14,dx[7:5]);
                    glyph_row=dy[4:1]; glyph_col=dx[4:1];
                end else if(interaction_osd && y>=336 && y<352 && x>=184 && x<456)begin
                    dx=x-184;dy=y-336;hit=1;
                    if(dx<64)glyph=word_glyph(exam_finished_frame ? 5'd29 : !exam_started_frame ? 5'd27 :
                        exam_running_frame ? 5'd30 : 5'd31,dx[6:4]);
                    else if(dx>=96 && dx<160 && !exam_started_frame)glyph=word_glyph(28,(dx-96)>>4);
                    else if(dx>=192 && dx<256 && !exam_finished_frame)glyph=word_glyph(29,(dx-192)>>4);
                    else hit=0;
                    glyph_row=dy[3:0];glyph_col=dx[3:0];
                end
            end else if (scene_visible && scene_frame==2) begin
                if (y>=128 && y<160 && x>=256 && x<384) begin
                    dx=x-256; dy=y-128; hit=1; style=6;
                    glyph=word_glyph(16,{1'd0,dx[6:5]});
                end else if (y>=192 && y<224 && x>=224 && x<416) begin
                    dx=x-224; dy=y-192; hit=1; style=7;
                    glyph=word_glyph(17,dx[7:5]);
                end
                glyph_row=dy[4:1]; glyph_col=dx[4:1];
            end else if(resolution_box && y>=24 && y<40 &&
                x>=resolution_text_x && x<resolution_text_x+{resolution_cells,4'd0})begin
                dx=x-resolution_text_x;dy=y-24;cell_index=dx[7:4];hit=1;style=1;
                if(cell_index==resolution_width_digits)glyph=9'd347;
                else if(cell_index<resolution_width_digits)
                    glyph=9'd300+{5'd0,dimension_digit(resolution_width_frame,resolution_width_digits,cell_index)};
                else glyph=9'd300+{5'd0,dimension_digit(resolution_height_frame,resolution_height_digits,
                    cell_index-resolution_width_digits-1'b1)};
                glyph_row=dy[3:0];glyph_col=dx[3:0];
            end

            if(mute_box && x>=556 && x<588 && y>=badge_y+12 && y<badge_y+28)begin
                dx=x-556;dy=y-badge_y-12;hit=1;style=0;
                glyph=word_glyph(25,{2'd0,dx[4]});glyph_row=dy[3:0];glyph_col=dx[3:0];
            end else if(auto_box && x>=auto_x+8 && x<auto_x+40 && y>=badge_y+8 && y<badge_y+24)begin
                dx=x-auto_x-8;dy=y-badge_y-8;hit=1;style=0;
                glyph=word_glyph(26,{2'd0,dx[4]});glyph_row=dy[3:0];glyph_col=dx[3:0];
            end else if(manual_box && x>=auto_x+8 && x<auto_x+40 && y>=badge_y+8 && y<badge_y+24)begin
                dx=x-auto_x-8;dy=y-badge_y-8;hit=1;style=0;
                glyph=dx[4] ? 9'd330 : 9'd338;glyph_row=dy[3:0];glyph_col=dx[3:0];
            end
            text_lookup={glyph,glyph_row,glyph_col,hit,style};
        end
    endfunction

    wire [9:0] look_x=de ? (pixel_x<638 ? pixel_x+10'd2 : pixel_x) : 10'd0;
    wire [8:0] look_y=!vs ? 9'd0 :
        (de_old && !de && pixel_y<479 ? pixel_y+9'd1 : pixel_y);
    wire [20:0] lookup_data=text_lookup(look_x,look_y);
    reg [20:0] glyph_request;
    reg [7:0] glyph_meta;
    wire [15:0] glyph_data,map_data;
    wire [6:0] glyph_index=glyph_request[20] ? glyph_request[18:12] :
        glyph_request[12] ? map_data[13:7] : map_data[6:0];
    photo_font_rom font_proc(.clk(clk),.enable(glyph_request[3]),
        .address({glyph_index,glyph_request[11:8]}),.row_data(glyph_data),
        .map_enable(lookup_data[3] && !lookup_data[20]),
        .map_address(11'd1472+{4'd0,lookup_data[19:13]}),.map_data(map_data));
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin glyph_meta<=0;glyph_request<=0;end
        else begin glyph_request<=lookup_data;glyph_meta<=glyph_request[7:0];end
    end
    wire subtitle_group=visible_index_out>=4;
    wire subtitle_page=visible_valid_out && visible_index_out>=1 && visible_index_out<=7 && scene_frame==0;
    wire [4:0] subtitle_length=subtitle_group ? teacher_length_frame : notice_length_frame;
    wire [9:0] subtitle_scroll=subtitle_group ? teacher_scroll : notice_scroll;
    wire subtitle_visible=subtitle_frame && subtitle_loaded && subtitle_page && subtitle_length!=0 &&
        video_visible && !underflow_flag;
    wire [11:0] subtitle_dx={2'd0,look_x}+{2'd0,subtitle_scroll}-12'd624;
    wire subtitle_lookup=subtitle_visible && look_x>=16 && look_x<624 && look_y>=448 && look_y<464 &&
        !subtitle_dx[11] && subtitle_dx<{3'd0,subtitle_length,4'd0};
    wire [5:0] subtitle_cell={subtitle_group,subtitle_dx[8:4]};
    wire subtitle_map_read=subtitle_lookup && (subtitle_dx[3:0]==0 || look_x==16);
    reg subtitle_map_pending,subtitle_row_ready;
    reg [3:0] subtitle_row_index;
    reg [15:0] subtitle_row_cache;
    wire [15:0] subtitle_word;
    wire [10:0] subtitle_read_addr=subtitle_map_pending ? {subtitle_word[6:0],subtitle_row_index} :
        11'd1472+{5'd0,subtitle_cell};
    photo_subtitle_ram subtitle_ram_proc(
        .mem_clk(mem_clk),.mem_en(subtitle_mem_en),.mem_write_en(subtitle_mem_write_en),
        .mem_addr(subtitle_mem_addr),.mem_write_data(subtitle_mem_write_data),.mem_read_data(subtitle_mem_read_data),
        .pix_clk(clk),.read_en(subtitle_map_read || subtitle_map_pending),.read_addr(subtitle_read_addr),.read_data(subtitle_word));
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin subtitle_map_pending<=0;subtitle_row_ready<=0;subtitle_row_index<=0;subtitle_row_cache<=0;end
        else begin
            subtitle_map_pending<=subtitle_map_read;subtitle_row_ready<=subtitle_map_pending;
            if(subtitle_map_read)subtitle_row_index<=look_y[3:0];
            if(subtitle_row_ready)subtitle_row_cache<=subtitle_word;
        end
    end
    wire [15:0] subtitle_row=subtitle_row_ready ? subtitle_word : subtitle_row_cache;
    wire [11:0] subtitle_pixel_dx={2'd0,pixel_x}+{2'd0,subtitle_scroll}-12'd624;
    wire subtitle_pixel_hit=pixel_y>=448 && pixel_y<464 && !subtitle_pixel_dx[11] &&
        subtitle_pixel_dx<{3'd0,subtitle_length,4'd0};
    function [6:0] interval_width;
        input [4:0] value;
        reg [6:0] width_value;
        begin
            width_value=({2'd0,value}<<1)+{2'd0,value}+{4'd0,value[4:2]};
            interval_width=width_value>96 ? 7'd96 : width_value;
        end
    endfunction
    reg [2:0] row_slot, row_item;
    reg [6:0] bar_width;
    reg row_hit;
    reg [23:0] text_color;
    reg [8:0] arrow_dy;
    reg [9:0] arrow_dx;
    always @* begin
        rgb_out=background_rgb; overlay_active=0;
        row_slot=0; row_item=0; bar_width=0; row_hit=0; text_color=24'heef3f5;
        arrow_dy=pixel_y>=302 ? pixel_y-9'd302 : 9'd302-pixel_y;
        arrow_dx=10'd396-pixel_x;
        if(menu_frame && de && pixel_x>=368 && pixel_x<624 && pixel_y>=16 && pixel_y<208) begin
            overlay_active=1; rgb_out=24'h111820;
            if(pixel_y>=56 && pixel_y<92)begin row_slot=0;row_hit=1;end
            else if(pixel_y>=92 && pixel_y<128)begin row_slot=1;row_hit=1;end
            else if(pixel_y>=128 && pixel_y<164)begin row_slot=2;row_hit=1;end
            row_item=window_start+row_slot;
            if(row_hit && row_item==menu_item_frame && pixel_x>=376 && pixel_x<616)rgb_out=24'h263a4b;
            case(row_item)
                0:bar_width={volume_frame,4'd0}+{1'd0,volume_frame,3'd0};
                1:bar_width={brightness_frame,4'd0}+{1'd0,brightness_frame,3'd0};
                2:bar_width=eye_frame==0 ? 0 : eye_frame==1 ? 48 : 96;
                3:bar_width=interval_width(slideshow_frame);
                4:bar_width=transition_mode_frame==0 ? 0 : transition_mode_frame==1 ? 48 : 96;
                5:bar_width=subtitle_frame ? 96 : 0;
                6:bar_width={subtitle_speed_frame,4'd0}+{1'b0,subtitle_speed_frame,3'd0};
                default:bar_width={subtitle_alpha_frame,4'd0}+{1'b0,subtitle_alpha_frame,3'd0};
            endcase
            if(pixel_x>=432 && pixel_x<528 &&
                ((pixel_y>=70 && pixel_y<76)||(pixel_y>=106 && pixel_y<112)||(pixel_y>=142 && pixel_y<148)))
                rgb_out=pixel_x-10'd432<{3'd0,bar_width} ? 24'hd9e5eb : 24'h354958;
            if((pixel_x==368 || pixel_x==623 || pixel_y==16 || pixel_y==207) ||
                ((pixel_y==52 || pixel_y==168) && pixel_x>=384 && pixel_x<608))rgb_out=24'h667f90;
        end else if(!menu_frame && scene_visible && de) begin
            if(scene_frame==1 && pixel_x>=176 && pixel_x<464 && pixel_y>=128 && pixel_y<352) begin
                overlay_active=1;
                rgb_out={8'd16+{4'd0,background_rgb[23:20]},8'd22+{4'd0,background_rgb[15:12]},
                    8'd30+{4'd0,background_rgb[7:4]}};
                if(pixel_x==176 || pixel_x==463 || pixel_y==128 || pixel_y==351)rgb_out=24'h667f90;
                if(pixel_y==272 && pixel_x>=200 && pixel_x<440)rgb_out=24'h354958;
                if(pixel_y>=328 && pixel_y<333 && pixel_x>=200 && pixel_x<440)
                    rgb_out=pixel_x-10'd200<{2'd0,progress_frame} ? status_color : 24'h354958;
            end else if(scene_frame==2 && pixel_x>=120 && pixel_x<520 && pixel_y>=96 && pixel_y<384)begin
                overlay_active=1;
                rgb_out={8'd46+{4'd0,background_rgb[23:20]},8'd24+{4'd0,background_rgb[15:12]},
                    8'd24+{4'd0,background_rgb[7:4]}};
                if(pixel_x==120 || pixel_x==519 || pixel_y==96 || pixel_y==383)rgb_out=24'hdb776d;
                if((pixel_x>=244 && pixel_x<320 && pixel_y>=290 && pixel_y<314) ||
                    (pixel_x>=320 && pixel_x<396 && pixel_y>=264 && pixel_y<340 &&
                     {1'd0,arrow_dy}<={1'b0,arrow_dx[9:1]}))
                    rgb_out=blink_on ? 24'h40ff80 : 24'h164e2a;
            end
        end
        if(de && resolution_box && pixel_x>=resolution_x && pixel_x<resolution_x+160 &&
            pixel_y>=16 && pixel_y<48)begin
            overlay_active=1;rgb_out=24'h000000;
            if(pixel_x==resolution_x || pixel_x==resolution_x+159 || pixel_y==16 || pixel_y==47)
                rgb_out=24'h667f90;
        end
        if(de && sound_box && pixel_x>=520 && pixel_x<624 && pixel_y>=badge_y && pixel_y<badge_y+40)begin
            overlay_active=1;rgb_out=24'h000000;
            if(pixel_x==520 || pixel_x==623 || pixel_y==badge_y || pixel_y==badge_y+39)rgb_out=24'h667f90;
            if((pixel_x>=528 && pixel_x<534 && pixel_y>=badge_y+16 && pixel_y<badge_y+24) ||
               (pixel_x>=534 && pixel_x<542 && pixel_y>=badge_y+10 && pixel_y<badge_y+30 &&
                (pixel_y>=badge_y+20 ? pixel_y-badge_y-20 : badge_y+20-pixel_y)<=pixel_x-532))rgb_out=24'heef3f5;
            if(mute_box && pixel_x>=528 && pixel_x<550 && pixel_y>=badge_y+9 && pixel_y<badge_y+31 &&
               ((pixel_x-528==pixel_y-badge_y-9)||(pixel_x-528==badge_y+30-pixel_y)))rgb_out=24'hff655b;
            if(unmute_box && volume_frame>=1 && pixel_x>=546 && pixel_x<550 &&
                (pixel_y>=badge_y+15 && pixel_y<badge_y+26) &&
                (pixel_y>=badge_y+20 ? pixel_y-badge_y-20 : badge_y+20-pixel_y)==pixel_x-545)rgb_out=24'heef3f5;
            if(unmute_box && volume_frame>=2 && pixel_x>=550 && pixel_x<554 &&
                (pixel_y>=badge_y+12 && pixel_y<badge_y+29) &&
                (pixel_y>=badge_y+20 ? pixel_y-badge_y-20 : badge_y+20-pixel_y)==pixel_x-549)rgb_out=24'heef3f5;
            if(unmute_box && volume_frame>=3 && pixel_x>=554 && pixel_x<558 &&
                (pixel_y>=badge_y+9 && pixel_y<badge_y+32) &&
                (pixel_y>=badge_y+20 ? pixel_y-badge_y-20 : badge_y+20-pixel_y)==pixel_x-553)rgb_out=24'heef3f5;
            if(unmute_box && volume_frame>=4 && pixel_x>=558 && pixel_x<562 &&
                (pixel_y>=badge_y+6 && pixel_y<badge_y+35) &&
                (pixel_y>=badge_y+20 ? pixel_y-badge_y-20 : badge_y+20-pixel_y)==pixel_x-557)rgb_out=24'heef3f5;
        end
        if(de && (auto_box || manual_box) && pixel_x>=auto_x && pixel_x<auto_x+48 && pixel_y>=badge_y && pixel_y<badge_y+32)begin
            overlay_active=1;rgb_out=24'h000000;
        end
        case(glyph_meta[2:0])
            1:text_color=24'hfff080;
            2:text_color=24'h9aaebc;
            3:text_color=24'hfff080;
            4:text_color=status_color;
            5:text_color=timer_color;
            6:text_color=blink_on ? 24'hffdfce : 24'h633c32;
            7:text_color=blink_on ? 24'hfff080 : 24'h685b28;
            default:text_color=24'heef3f5;
        endcase
        if(de && overlay_active && glyph_meta[3] && glyph_data[15-glyph_meta[7:4]])rgb_out=text_color;
        if(de && subtitle_visible && pixel_x>=16 && pixel_x<624 && pixel_y>=440 && pixel_y<472)begin
            overlay_active=1;
            rgb_out={brightness_proc(background_rgb[23:16],subtitle_alpha_frame),
                brightness_proc(background_rgb[15:8],subtitle_alpha_frame),brightness_proc(background_rgb[7:0],subtitle_alpha_frame)};
            if(subtitle_pixel_hit && subtitle_row[15-subtitle_pixel_dx[3:0]])rgb_out=24'heef3f5;
        end
    end
endmodule
