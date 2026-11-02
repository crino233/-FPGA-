`timescale 1ns/1ps
module tb_photo_ten #(
    parameter integer full_size=0,
    parameter integer all_bad=0,
    parameter integer bad_first=0,
    parameter integer scene_audio=0,
    parameter integer badge_return=0,
    parameter integer transition_mode_value=0,
    parameter integer group_prefetch_value=0,
    parameter integer scene_switch_value=0,
    parameter integer manual_priority_value=0,
    parameter integer subtitle_value=0,
    parameter integer subtitle_service_value=0,
    parameter integer wav_value=0,
    parameter integer image_scale_value=0,
    parameter integer startup_only=0,
    parameter integer sector_delay_cycles=0,
    parameter integer font_cache_value=0,
    parameter integer culture_priority_value=0
);
    localparam integer width_val=full_size ? 640 : 32,
        height_val=full_size ? 480 : image_scale_value ? 24 : manual_priority_value ? 32 : 8;
    localparam integer image_words=width_val*height_val, bmp_size=image_words*3+54;
    localparam integer file_sectors=image_scale_value ? (full_size ? 1921 : 73) : (bmp_size+511)/512,
        cluster_spacing=10000;
    reg clk=0,pix_clk=0,rst_n=0;
    reg culture_auto=0,culture_auto_step=0;
    always #4 clk=~clk;
    always #20 pix_clk=~pix_clk;
    integer result_file, sectors=0;
    wire wav_ready,wav_consume;
    wire signed [15:0] wav_sample;
    wire [7:0] wav_error;
    reg [1:0] wav_scene=0;
    reg [7:0] wav_corpus[0:10055];reg [15:0] wav_expected[0:4999];
    integer wav_samples=0;
    initial if(wav_value)begin $readmemh("work/wav_fixture.hex",wav_corpus);$readmemh("work/wav_expected.hex",wav_expected);end
    string test_name;
    integer refresh_count=0,refresh_gap=0,max_refresh_gap=0;
    wire ready,busy,refreshing,wr_en,rd_en,rd_valid;
    wire [20:0] wr_addr,rd_addr;
    wire [31:0] wr_data,rd_data;
    wire [3:0] wr_mask,complete,active_index,display_index,requested_index;
    wire [11:0] active_source_width,active_source_height;
    wire [9:0] valid_mask;
    wire display_ready,wr_req,wr_grant,wr_done,rd_req,rd_grant,rd_done;
    wire refresh_request,target_ready,display_publish_enable,transition_busy;
    wire [1:0] display_bank,active_bank;
    wire [1:0] transition_mode=transition_mode_value;
    wire [7:0] transition_alpha;
    wire transition_wipe_active;
    wire [4:0] transition_wipe_ramp;
    wire [3:0] status_code;
    wire [7:0] ingest_error,error_detail,reader_error,player_error;
    reg next_down=0,prev_down=0,auto_down=0,tick_1ms=0;
    wire frame_commit,request_busy,auto_mode;
    wire subtitle_request,subtitle_start,subtitle_valid,subtitle_end,subtitle_finished,subtitle_cancelled,subtitle_done;
    wire subtitle_ready,subtitle_mem_en,subtitle_mem_write_en;
    wire [1:0] subtitle_index;
    wire [31:0] subtitle_size,subtitle_offset;
    wire [31:0] subtitle_range_offset;
    wire subtitle_close;
    wire [7:0] subtitle_data,subtitle_file_error,subtitle_load_error,subtitle_error;
    wire [4:0] subtitle_notice_length,subtitle_teacher_length;
    reg [6:0] subtitle_character_map[0:63];
    wire [10:0] subtitle_mem_addr;
    wire [15:0] subtitle_mem_write_data,subtitle_mem_read_data;
    always @(posedge clk)if(subtitle_value && subtitle_mem_en && subtitle_mem_write_en && subtitle_mem_addr>=1472 && subtitle_mem_addr<1536)
        subtitle_character_map[subtitle_mem_addr-1472]=subtitle_mem_write_data[6:0];
    reg [15:0] subtitle_expected_rows[0:2047];
    reg [7:0] subtitle_font[0:745215];
    integer subtitle_checked_pixels=0;
    integer frame_image,frames=0;
    reg video_check=0;
    initial $readmemh("photo_subtitle_font.dath",subtitle_expected_rows);
    always @(posedge clk)if(font_cache_value && subtitle_mem_en && subtitle_mem_write_en &&
        subtitle_mem_addr>=1280 && subtitle_mem_addr<1360 && subtitle_mem_write_data!=0)begin: oracle_proc
        integer glyph_pos,slot_pos;
        slot_pos=subtitle_mem_addr-1280;
        glyph_pos={subtitle_font[512+subtitle_mem_write_data*4],subtitle_font[513+subtitle_mem_write_data*4]};
        if(glyph_pos>=7540)$fatal(1,"oracle glyph outside font");
        subtitle_expected_rows[1280+slot_pos]=subtitle_mem_write_data;
        for(integer row=0;row<16;row=row+1)
            subtitle_expected_rows[slot_pos*16+row]={subtitle_font[262658+glyph_pos*64+row*2],
                subtitle_font[262659+glyph_pos*64+row*2]};
    end
    reg [7:0] subtitle_notice[0:127],subtitle_teacher[0:127];
    integer subtitle_font_size=0,subtitle_notice_size,subtitle_teacher_size,subtitle_fd,subtitle_cancels=0;
    initial if(subtitle_value)begin
        subtitle_fd=$fopen("fixtures/card_a/NOTICE.TXT","rb");
        if(subtitle_fd==0)$fatal(1,"missing fixed card_a NOTICE fixture");
        subtitle_notice_size=$fread(subtitle_notice,subtitle_fd);$fclose(subtitle_fd);
        subtitle_fd=$fopen("fixtures/card_a/TEACHER.TXT","rb");
        if(subtitle_fd==0)$fatal(1,"missing fixed card_a TEACHER fixture");
        subtitle_teacher_size=$fread(subtitle_teacher,subtitle_fd);$fclose(subtitle_fd);
        if(subtitle_value==3)begin subtitle_notice[0]=8'he6;subtitle_notice[1]=8'hb5;subtitle_notice[2]=8'hb7;subtitle_notice_size=3;end
        if(font_cache_value)begin
            subtitle_fd=$fopen("tf_card/FONT16.BIN","rb");
            subtitle_font_size=$fread(subtitle_font,subtitle_fd);$fclose(subtitle_fd);
            subtitle_notice[0]=8'he6;subtitle_notice[1]=8'hb5;subtitle_notice[2]=8'hb7;
        end
    end
    generate if(subtitle_value)begin: subtitle_proc
        photo_subtitle_load #(.external_font(subtitle_value!=3)) loader(
            .clk(clk),.rst_n(rst_n),.enable(display_ready),.file_request(subtitle_request),.file_index(subtitle_index),
            .range_offset(subtitle_range_offset),.file_close(subtitle_close),
            .file_start(subtitle_start),.file_valid(subtitle_valid),.file_end(subtitle_end),.file_finished(subtitle_finished),
            .file_cancelled(subtitle_cancelled),.file_size(subtitle_size),.file_offset(subtitle_offset),.file_data(subtitle_data),
            .file_error(subtitle_file_error),.load_done(subtitle_done),.load_error(subtitle_load_error),.ready(subtitle_ready),
            .error_code(subtitle_error),.notice_length(subtitle_notice_length),.teacher_length(subtitle_teacher_length),
            .mem_en(subtitle_mem_en),.mem_write_en(subtitle_mem_write_en),.mem_addr(subtitle_mem_addr),
            .mem_write_data(subtitle_mem_write_data),.mem_read_data(subtitle_mem_read_data));
    end else begin: no_subtitle_proc
        assign subtitle_request=0;
        assign subtitle_index=0;
        assign subtitle_done=0;
        assign subtitle_load_error=0;
    end endgenerate
    generate if(subtitle_value && !full_size)begin: subtitle_rom_proc
        photo_subtitle_ram rom(
            .mem_clk(clk),.mem_en(subtitle_mem_en),.mem_write_en(subtitle_mem_write_en),.mem_addr(subtitle_mem_addr),
            .mem_write_data(subtitle_mem_write_data),.mem_read_data(subtitle_mem_read_data),
            .pix_clk(pix_clk),.read_en(1'b0),.read_addr(11'd0),.read_data());
    end endgenerate
    wire player_auto,badge_auto,badge_next,badge_prev,badge_step,badge_consume,badge_target_valid;
    wire [3:0] badge_target_index;
    wire [1:0] badge_group,badge_scene;
    reg badge_exam=0,badge_fire=0,badge_config_apply=0;
    reg [9:0] group_selection=10'h00e;
    reg group_target_valid=0;
    reg [3:0] group_target_index=1;
    reg [2:0] badge_short=0,badge_long=0;
    wire timer_finished,timer_running;
    wire [31:0] timer_seconds;
    wire [9:0] selection_mask=badge_return ? (badge_scene==2 ? 10'b1000000000 : badge_scene==1 ? 10'b0100000000 :
        badge_group==2 ? 10'b0000000001 : badge_group==1 ? 10'b0011110000 : 10'b0000001110) :
        group_prefetch_value ? group_selection : 10'h3ff;
    reg startup_image_latched=0;
    always @(posedge clk) if(!rst_n)startup_image_latched<=0;
        else if(display_ready)startup_image_latched<=1;
    wire [3:0] ingest_requested_index=(badge_return || group_prefetch_value) && !startup_image_latched ? 4'd1 : requested_index;
    assign auto_mode=badge_return ? badge_auto : player_auto;
    generate if(badge_return)begin: badge_proc
        wire start_toggle,duration_step,reset_cmd,pause_cmd;
        wire [2:0] duration_index;
        photo_badge_control control_proc (
            .clk(clk),.rst_n(rst_n),.enable(display_ready && reader_error==0),.tick_1ms(tick_1ms),
            .short_event(badge_short),.long_event(badge_long),.key1_short_event(1'b0),.exam_request(badge_exam),
            .fire_request(badge_fire),.music_mute(1'b0),.player_busy(request_busy || transition_busy),
            .frame_commit(frame_commit),.active_index(active_index),
            .exam_done(timer_finished),
            .config_apply(badge_config_apply),.config_data({3'd1,3'd2,1'b0,2'd0,1'b0,2'd0,3'd6,5'd30,3'd4,3'd4}),
            .player_next_down(badge_next),.player_prev_down(badge_prev),.player_auto_step(badge_step),
            .auto_mode(badge_auto),.consume_event(badge_consume),.temporary_pause(),
            .page_group(badge_group),.page_change(),.page_return_index(),.page_return_valid(),
            .page_select_valid(badge_target_valid),.page_select_index(badge_target_index),
            .menu_active(),.menu_item(),.menu_adjust(),.music_volume(),.brightness_level(),
            .eye_mode(),.slideshow_ms(),.slideshow_seconds(),
            .exam_start_toggle(start_toggle),.exam_duration_step(duration_step),.exam_reset(reset_cmd),
            .exam_pause(pause_cmd),.exam_finish(),.exam_started(),.exam_running(),.exam_finished(),
            .exam_duration_index(duration_index),.music_enable(),.scene_mode(badge_scene));
        photo_exam_timer timer_proc (
            .clk(clk),.rst_n(rst_n),.tick_1ms(tick_1ms),.exam_enable(badge_exam),.pause_active(1'b0),
            .start_toggle(start_toggle),.duration_step(duration_step),.reset_cmd(reset_cmd),.pause_cmd(pause_cmd),
            .duration_index(duration_index),.remaining_seconds(timer_seconds),.remaining_minutes(),
            .remaining_second(),.running(timer_running),.finished(timer_finished));
    end endgenerate
    photo_ingest #(.image_width(width_val),.image_height(height_val),
        .group_prefetch(badge_return || group_prefetch_value),.subtitle_support(subtitle_value!=0 || subtitle_service_value),
        .wav_support(wav_value),.image_scale_support(image_scale_value)) dut (
        .clk(clk),.rst_n(rst_n),.controller_ready(ready),.controller_busy(busy),.refresh_active(refreshing),
         .requested_index(ingest_requested_index),
         .active_bank(active_bank),.auto_mode(auto_mode),.display_publish_enable(display_publish_enable),
        .selection_mask(selection_mask),
        .wav_play_enable(wav_scene==0),.wav_pix_clk(pix_clk),.wav_pix_rst_n(rst_n),.wav_consume(wav_consume),
        .wav_sample(wav_sample),.wav_ready(wav_ready),.wav_error(wav_error),
        .memory_grant(wr_grant),.memory_request(wr_req),.memory_done(wr_done),
        .display_ready(display_ready),.display_bank(display_bank),.display_index(display_index),.active_index(active_index),
        .active_source_width(active_source_width),.active_source_height(active_source_height),
         .target_ready(target_ready),
        .valid_mask(valid_mask),.image_complete(complete),.status_code(status_code),
        .error_code(ingest_error),.error_detail(error_detail),
        .subtitle_request(subtitle_request),.subtitle_index(subtitle_index),.subtitle_done(subtitle_done),
        .subtitle_range_offset(subtitle_range_offset),.subtitle_close(subtitle_close),
        .subtitle_service_complete(subtitle_value==0 || subtitle_ready || subtitle_error!=0),
        .subtitle_load_error(subtitle_load_error),.subtitle_start(subtitle_start),.subtitle_valid(subtitle_valid),
        .subtitle_end(subtitle_end),.subtitle_finished(subtitle_finished),.subtitle_cancelled(subtitle_cancelled),
        .subtitle_size(subtitle_size),.subtitle_offset(subtitle_offset),.subtitle_data(subtitle_data),.subtitle_file_error(subtitle_file_error),
        .app_wr_en(wr_en),.app_wr_addr(wr_addr),.app_wr_data(wr_data),.app_wr_mask(wr_mask),
        .sd_cs_n(),.sd_sclk(),.sd_mosi(),.sd_miso(1'b1)
    );
    photo_player_control #(.image_count(10),.auto_period_ms(3),
        .external_control(badge_return || group_prefetch_value)) player (
        .clk(clk),.rst_n(rst_n),.enable(display_ready),.tick_1ms(tick_1ms),
        .next_down(badge_return ? badge_next : next_down),.auto_down(auto_down),
        .prev_down(badge_return ? badge_prev : prev_down),
        .external_auto(group_prefetch_value ? culture_auto : badge_auto),
        .auto_step(group_prefetch_value ? culture_auto_step : badge_step),
        .discard_events(group_prefetch_value ? 1'b0 : badge_consume),
        .selection_mask(selection_mask),
        .target_valid(group_prefetch_value ? group_target_valid : badge_target_valid),
        .target_index(group_prefetch_value ? group_target_index : badge_target_index),
         .frame_commit(frame_commit && !transition_busy),.active_index(active_index),.valid_mask(valid_mask),
        .image_index(requested_index),.auto_mode(player_auto),.request_busy(request_busy),.timer_en(),.error_code(player_error)
    );
    photo_memory_arbiter arbiter (
        .clk(clk),.rst_n(rst_n),.controller_ready(ready),.controller_busy(busy),.refresh_active(refreshing),
        .write_request(wr_req),.read_request(rd_req),.write_done(wr_done),.read_done(rd_done),
        .write_grant(wr_grant),.read_grant(rd_grant),.refresh_request(refresh_request)
    );
    reg frame_sync=1,read_req=0,read_en=0;
    wire read_ack,frame_ready,underflow;
    wire [31:0] pixel;
    wire official_req,official_read_en,official_vs,video_de;
    wire [23:0] video_pixel;
    wire final_vs;
    wire [23:0] transition_pixel;
    wire transition_frame_sync=full_size ? official_vs : frame_sync;
    reg transition_frame_sync_old=1;
    reg transition_visible_valid_q=0;
    reg [3:0] transition_visible_index_q=0;
    wire transition_visible_valid;
    wire [3:0] transition_visible_index;
    wire transition_incoming_valid,transition_frame_start,transition_scene_visible,transition_visible_frame_pulse;
    wire [3:0] transition_incoming_index;
    generate if(wav_value)begin: product_audio_proc
        photo_audio_product product_audio(
            .mem_clk(clk),.mem_rst_n(rst_n),.clk(pix_clk),.rst_n(rst_n),
            .scene_mode(wav_scene),.menu_active(1'b0),.music_enable(1'b1),.music_volume(3'd4),
            .source_enable(display_ready && reader_error==0),.error_flag(),
            .exam_running(1'b0),.exam_finished(1'b0),.exam_reset(1'b0),.remaining_seconds(32'd1800),
            .frame_sync(official_vs),.video_de(video_de),.video_visible(frame_ready),.underflow_flag(underflow),
            .visible_valid(transition_visible_valid),.visible_index(transition_visible_index),
            .scene_visible(transition_scene_visible),.visible_frame_pulse(transition_visible_frame_pulse),.reader_error(reader_error),
            .hdmi_video_locked(1'b1),
            .wav_ready(wav_ready),.wav_sample(wav_sample),.sample_tick(),.wav_consume(wav_consume),
            .audio_valid(),.audio_left_data(),.audio_right_data(),.acr_valid(),.acr_cts(),.acr_n(),.music_ready(),.effect_active());
        always @(posedge pix_clk)if(rst_n && wav_consume && wav_ready)begin
            if(wav_sample!==wav_expected[wav_samples%5000])$fatal(1,"full image/WAV PCM mismatch at %d",wav_samples);
            wav_samples<=wav_samples+1;
        end
    end else begin: no_product_audio_proc
        assign wav_consume=1'b0;
    end endgenerate
    always @(posedge pix_clk or negedge rst_n) begin
        if(!rst_n)transition_frame_sync_old<=1;
        else transition_frame_sync_old<=transition_frame_sync;
    end
    generate if(full_size) begin: video_proc
        wire hs_0,de_0,hs,vs;
        video_timing_data timing (
            .video_clk(pix_clk),.rst(!rst_n),.read_req(official_req),.read_req_ack(read_ack),
            .hs(hs_0),.vs(official_vs),.de(de_0)
        );
        video_delay delay_proc (
            .video_clk(pix_clk),.rst(!rst_n),.read_en(official_read_en),.read_data(pixel[23:0]),
            .hs(hs_0),.vs(official_vs),.de(de_0),.hs_r(hs),.vs_r(vs),.de_r(video_de),.vout_data(video_pixel)
        );
        assign final_vs=vs;
    end endgenerate
    generate if(full_size && (transition_mode_value!=0 || subtitle_value!=0))begin: overlay_proc
        photo_badge_overlay overlay (
            .mem_clk(clk),.mem_rst_n(rst_n),.clk(pix_clk),.rst_n(rst_n),
            .vs(final_vs),.de(video_de),.rgb_in(video_pixel),
            .frame_sync(official_vs),.frame_commit(frame_commit),.active_index(active_index),
            .active_source_width(active_source_width),.active_source_height(active_source_height),
            .video_visible(frame_ready),.underflow_flag(underflow),
            .menu_active(1'b0),.menu_item(3'd0),.music_volume(3'd4),.brightness_level(3'd4),
            .music_mute(1'b0),.auto_notice(1'b0),.manual_notice(1'b0),.resolution_notice(1'b0),
            .tick_1ms(tick_1ms),.manual_pause(1'b0),
            .eye_mode(2'd0),.transition_mode(transition_mode),
            .subtitle_enable(subtitle_value!=0),.subtitle_speed(3'd2),.subtitle_alpha(3'd1),.subtitle_ready(subtitle_value ? subtitle_ready : 1'b0),
            .subtitle_notice_length(subtitle_notice_length),.subtitle_teacher_length(subtitle_teacher_length),
            .subtitle_mem_en(subtitle_mem_en),.subtitle_mem_write_en(subtitle_mem_write_en),.subtitle_mem_addr(subtitle_mem_addr),
            .subtitle_mem_write_data(subtitle_mem_write_data),.subtitle_mem_read_data(subtitle_mem_read_data),
            .transition_alpha(transition_alpha),.transition_wipe_active(transition_wipe_active),
            .transition_wipe_ramp(transition_wipe_ramp),.slideshow_seconds(5'd5),.scene_mode(2'd0),
            .exam_started(1'b0),.exam_running(1'b0),.exam_finished(1'b0),
            .exam_duration_index(3'd0),.exam_minutes(8'd30),.exam_second(6'd0),
            .rgb_out(transition_pixel),.overlay_active(),.frame_start_out(transition_frame_start),
            .visible_valid_out(transition_visible_valid),.visible_index_out(transition_visible_index),
             .incoming_valid_out(transition_incoming_valid),.incoming_index_out(transition_incoming_index),
             .scene_visible_out(transition_scene_visible),.visible_frame_pulse_out(transition_visible_frame_pulse)
        );
    end else begin: overlay_bypass_proc
        assign transition_pixel=video_pixel;
        assign transition_visible_valid=transition_visible_valid_q;
        assign transition_visible_index=transition_visible_index_q;
        assign transition_incoming_valid=transition_visible_valid_q;
        assign transition_incoming_index=transition_visible_index_q;
        assign transition_frame_start=transition_frame_sync_old && !transition_frame_sync;
        assign transition_scene_visible=1'b0;
        assign transition_visible_frame_pulse=1'b0;
    end endgenerate
    generate if(full_size && subtitle_value)begin: subtitle_check_proc
        integer x,y,dx,cell_index,slot;
        reg [23:0] expected;
        always @(negedge pix_clk)if(video_check && video_de)begin
            x=overlay_proc.overlay.pixel_x;y=overlay_proc.overlay.pixel_y;expected=video_pixel;
            if(overlay_proc.overlay.subtitle_visible && x>=16 && x<624 && y>=440 && y<472)begin
                expected={2'd0,video_pixel[23:18],2'd0,video_pixel[15:10],2'd0,video_pixel[7:2]};
                dx=x+overlay_proc.overlay.subtitle_scroll-624;
                if(y>=448 && y<464 && dx>=0 && dx<overlay_proc.overlay.subtitle_length*16)begin
                    cell_index=dx/16+(frame_image>=4 ? 32 : 0);slot=subtitle_character_map[cell_index];
                    if(subtitle_expected_rows[slot*16+y-448][15-dx%16])expected=24'heef3f5;
                end
                subtitle_checked_pixels=subtitle_checked_pixels+1;
            end
            if(transition_pixel!==expected)$fatal(1,"full subtitle phase/pixel x=%0d y=%0d got=%h exp=%h",x,y,transition_pixel,expected);
        end
    end endgenerate
    photo_frame_reader #(.image_words(image_words),.arbitrated(1)) reader (
        .mem_clk(clk),.mem_rst_n(rst_n),.pix_clk(pix_clk),.pix_rst_n(rst_n),
        .display_ready(display_ready),.image_index(display_bank),
        .controller_ready(ready),.controller_busy(busy),.refresh_active(refreshing),
        .memory_grant(rd_grant),.memory_request(rd_req),.memory_done(rd_done),
        .app_rd_en(rd_en),.app_rd_addr(rd_addr),.sdram_rd_valid(rd_valid),.sdram_rd_data(rd_data),
        .frame_sync(full_size ? official_vs : frame_sync),.read_req(full_size ? official_req : read_req),
        .read_req_ack(read_ack),.read_en(full_size ? official_read_en : read_en),.read_data(pixel),
        .underflow_flag(underflow),.error_code(reader_error),.frame_commit(frame_commit),.active_index(active_bank),
        .frame_ready(frame_ready)
    );
    photo_transition_control transition_proc (
        .mem_clk(clk),.mem_rst_n(rst_n),
        .allow_transition(badge_return ? badge_scene==0 : 1'b1),
        .transition_mode(transition_mode),.display_ready(display_ready),
        .requested_index(ingest_requested_index),.display_index(display_index),.target_ready(target_ready),
        .display_publish_enable(display_publish_enable),.transition_busy(transition_busy),
        .pix_clk(pix_clk),.pix_rst_n(rst_n),.frame_start(transition_frame_start),
        .incoming_valid(transition_incoming_valid),.incoming_index(transition_incoming_index),
        .visible_valid(transition_visible_valid),.visible_index(transition_visible_index),
        .background_alpha(transition_alpha),.wipe_active(transition_wipe_active),
        .wipe_ramp(transition_wipe_ramp)
    );
    wire audio_valid,acr_valid,audio_error;
    wire [23:0] audio_left_data,audio_right_data;
    wire [19:0] acr_n,acr_cts;
    wire [31:0] audio_sample_count,audio_acr_count;
    wire [1:0] audio_scene=active_index==9 ? 2'd2 : active_index==8 ? 2'd1 : 2'd0;
    photo_audio #(.image_count(10),.scene_audio(scene_audio)) audio_proc (
        .mem_clk(clk),.mem_rst_n(rst_n),.pix_clk(pix_clk),.pix_rst_n(rst_n),
        .source_enable(display_ready && reader_error==0),.frame_commit(frame_commit),.music_enable(1'b1),
        .audio_scene(audio_scene),.music_volume(3'd4),
        .active_index(active_index),
        .frame_sync(full_size ? official_vs : frame_sync),.video_de(full_size ? video_de : read_en),
        .video_visible(frame_ready),.underflow_flag(underflow),
        .audio_valid(audio_valid),.audio_left_data(audio_left_data),.audio_right_data(audio_right_data),
        .acr_valid(acr_valid),.acr_n(acr_n),.acr_cts(acr_cts),.error_flag(audio_error)
    );
    photo_audio_monitor audio_monitor_proc (
        .clk(pix_clk),.rst_n(rst_n),.audio_enable(audio_proc.audio_enable),
        .sample_valid(audio_valid),.left_data(audio_left_data),.right_data(audio_right_data),
        .acr_valid(acr_valid),.acr_n(acr_n),.acr_cts(acr_cts),
        .sample_count(audio_sample_count),.acr_count(audio_acr_count)
    );
    wire sdram_clk,ras_n,cas_n,we_n;
    wire [1:0] sdram_bank;
    wire [10:0] address;
    wire [3:0] mask;
    tri [31:0] dq;
    sdr_as_ram #(.self_refresh_open(1'b1)) controller (
        .Sdr_clk(clk),.Sdr_clk_sft(~clk),.Rst(!rst_n),
        .Sdr_init_done(ready),.Sdr_init_ref_vld(refreshing),.Sdr_busy(busy),.App_ref_req(refresh_request),
        .App_wr_en(wr_en),.App_wr_addr(wr_addr),.App_wr_dm(wr_mask),.App_wr_din(wr_data),
        .App_rd_en(rd_en),.App_rd_addr(rd_addr),.Sdr_rd_en(rd_valid),.Sdr_rd_dout(rd_data),
        .SDRAM_CLK(sdram_clk),.SDR_RAS(ras_n),.SDR_CAS(cas_n),.SDR_WE(we_n),
        .SDR_BA(sdram_bank),.SDR_ADDR(address),.SDR_DM(mask),.SDR_DQ(dq)
    );
    photo_sdram_model #(.memory_words(image_words*4)) memory (
        .clk(sdram_clk),.rst(!rst_n),.ready(ready),.ras_n(ras_n),.cas_n(cas_n),.we_n(we_n),
        .bank(sdram_bank),.address(address),.mask(mask),.dq(dq)
    );
    function automatic integer source_width_proc(input integer image);
        if(!image_scale_value)source_width_proc=width_val;
        else case(image)
            1:source_width_proc=full_size ? 641 : 65;
            2:source_width_proc=full_size ? 800 : 97;
            4:source_width_proc=full_size ? 480 : 96;
            5:source_width_proc=full_size ? 400 : 64;
            6:source_width_proc=full_size ? 320 : 64;
            7:source_width_proc=full_size ? 639 : 127;
            default:source_width_proc=full_size ? 640 : 64;
        endcase
    endfunction
    function automatic integer source_height_proc(input integer image);
        if(!image_scale_value)source_height_proc=height_val;
        else case(image)
            1:source_height_proc=full_size ? 479 : 97;
            2:source_height_proc=full_size ? 400 : 65;
            4:source_height_proc=full_size ? 480 : 96;
            5:source_height_proc=full_size ? 800 : 128;
            6:source_height_proc=full_size ? 240 : 64;
            7:source_height_proc=full_size ? 511 : 65;
            default:source_height_proc=full_size ? 480 : 64;
        endcase
    endfunction
    function automatic integer source_size_proc(input integer image);
        begin
            source_size_proc=54+((source_width_proc(image)*3+3)/4*4)*source_height_proc(image);
            if(image_scale_value==3 && image==6)source_size_proc=source_size_proc-8;
        end
    endfunction
    function automatic [23:0] source_rgb_proc(input integer image,input integer x,input integer y);
        source_rgb_proc={8'(image*19+11),8'(y),8'(x)};
    endfunction
    function automatic [23:0] expected_pixel(input integer image,input integer pos);
        integer sw,sh,k,cw,ch,x,y;
        begin
            x=pos%width_val;y=pos/width_val;
            if(image_scale_value)begin
                sw=source_width_proc(image);sh=source_height_proc(image);
                k=sw/4<sh/3 ? sw/4 : sh/3;cw=k*4;ch=k*3;
                x=(sw-cw)/2+((2*x+1)*cw)/(2*width_val);
                y=(sh-ch)/2+((2*y+1)*ch)/(2*height_val);
            end
            expected_pixel=source_rgb_proc(image,x,y);
        end
    endfunction
    function automatic [7:0] bmp_byte(input integer image,input integer offset);
        reg [23:0] rgb;
        integer pos,sw,sh,stride,x,y;
        begin
            bmp_byte=0;
            sw=source_width_proc(image);sh=source_height_proc(image);stride=(sw*3+3)/4*4;
            case(offset)
                0:bmp_byte="B"; 1:bmp_byte="M";
                2,3,4,5:bmp_byte=source_size_proc(image)>>((offset-2)*8);
                10:bmp_byte=54;14:bmp_byte=40;
                18,19,20,21:bmp_byte=(image_scale_value==3 && image==4 ? 0 : sw)>>((offset-18)*8);
                22,23,24,25:bmp_byte=(image_scale_value && image%2 ? sh : -sh)>>((offset-22)*8);
                26:bmp_byte=1;28:bmp_byte=image_scale_value==3 && image==3 ? 16 : 24;
                30:if((!badge_return && !group_prefetch_value &&
                    (all_bad || (bad_first && image==0) || image==1 || image==6)) ||
                    (image_scale_value==3 && image==2)) bmp_byte=1;
                default:if(offset>=54 && offset<source_size_proc(image)) begin
                    pos=(offset-54)%stride;x=pos/3;y=(offset-54)/stride;
                    if(image_scale_value && image%2)y=sh-1-y;
                    rgb=source_rgb_proc(image,x,y);
                    bmp_byte=x<sw ? rgb>>((pos%3)*8) : 8'he7;
                end
            endcase
        end
    endfunction
    function automatic [7:0] disk_byte(input integer lba,input integer offset);
        integer cluster,image,entry,pos;
        reg [31:0] value;
        begin
            disk_byte=0;
            if(lba==0) begin
                case(offset)
                    11:disk_byte=0;12:disk_byte=2;13:disk_byte=1;14:disk_byte=32;16:disk_byte=2;
                    32,33,34,35:disk_byte=131072>>((offset-32)*8);
                    37:disk_byte=4;44:disk_byte=2;510:disk_byte=8'h55;511:disk_byte=8'haa;
                endcase
            end else if(lba>=32 && lba<1056) begin
                cluster=(lba-32)*128+offset/4;
                value=32'h0fffffff;
                if(cluster==2) value=4;
                for(integer i=0;i<10;i=i+1)
                    if(cluster>=10+i*cluster_spacing && cluster<10+i*cluster_spacing+file_sectors-1)
                        value=cluster+1;
                if(wav_value && cluster>=98020 && cluster<98058 && !(cluster%2))value=cluster+2;
                if(font_cache_value && cluster>=99000 && cluster<99000+(subtitle_font_size+511)/512-1)value=cluster+1;
                disk_byte=value>>((offset%4)*8);
            end else if(lba==2080) begin
                if(offset%32==0) disk_byte=8'he5;
            end else if(lba==2082) begin
                entry=offset/32; pos=offset%32;
                if(entry<=8 || entry==15) begin
                    image=entry==15 ? 9 : entry;
                    case(pos)
                        0:disk_byte="P";1:disk_byte="I";2:disk_byte="C";
                        3:disk_byte=image==9 ? "1" : "1"+image;
                        4:disk_byte=image==9 ? "0" : " ";5,6,7:disk_byte=" ";
                        8:disk_byte="B";9:disk_byte="M";10:disk_byte="P";11:disk_byte=8'h21;
                        20,21:disk_byte=(10+image*cluster_spacing)>>(16+(pos-20)*8);
                        26,27:disk_byte=(10+image*cluster_spacing)>>((pos-26)*8);
                        28,29,30,31:begin
                            value=!badge_return && !group_prefetch_value && image==1 ? 4194304 :
                                (!badge_return && !group_prefetch_value && image==6 ? 64 : source_size_proc(image));
                            disk_byte=value>>((pos-28)*8);
                        end
                    endcase
                end else if(subtitle_value && entry>=10 && entry<=12 && !(subtitle_value==2 && entry==10) &&
                    !(font_cache_value==3 && entry==12))begin
                    case(pos)
                        0,1,2,3,4,5,6,7,8,9,10:case(entry)
                            10:disk_byte=88'h4e4f544943452020545854>>(80-pos*8);
                            11:disk_byte=88'h5445414348455220545854>>(80-pos*8);
                            12:disk_byte=88'h464f4e543136202042494e>>(80-pos*8);
                        endcase
                        11:disk_byte=8'h20;
                        20,21:disk_byte=(entry==10 ? 98000 : entry==11 ? 98001 : 99000)>>(16+(pos-20)*8);
                        26,27:disk_byte=(entry==10 ? 98000 : entry==11 ? 98001 : 99000)>>((pos-26)*8);
                        28,29,30,31:disk_byte=(entry==10 ? subtitle_notice_size : entry==11 ? subtitle_teacher_size : subtitle_font_size)>>((pos-28)*8);
                    endcase
                end else if(wav_value && entry==13)begin
                    case(pos)
                        0,1,2,3,4,5,6,7,8,9,10:disk_byte=88'h42474d2020202020574156>>(80-pos*8);
                        11:disk_byte=8'h20;
                        20,21:disk_byte=98020>>(16+(pos-20)*8);
                        26,27:disk_byte=98020>>((pos-26)*8);
                        28,29,30,31:disk_byte=10056>>((pos-28)*8);
                    endcase
                end else if(pos==0) disk_byte=8'he5;
            end else begin
                if(wav_value && lba>=100098 && lba<=100136 && !(lba%2))begin
                    pos=((lba-100098)/2)*512+offset;if(pos<10056)disk_byte=wav_corpus[pos];
                end
                if(subtitle_value)begin
                    if(lba==100078 && offset<subtitle_notice_size)disk_byte=subtitle_notice[offset];
                    if(lba==100079 && offset<subtitle_teacher_size)disk_byte=subtitle_teacher[offset];
                    if(lba>=101078 && lba<101078+(subtitle_font_size+511)/512)begin
                        pos=(lba-101078)*512+offset;
                        disk_byte=font_cache_value && pos<subtitle_font_size ? subtitle_font[pos] : 0;
                    end
                end
                for(integer i=0;i<10;i=i+1)
                    if(lba>=2088+i*cluster_spacing && lba<2088+i*cluster_spacing+file_sectors)
                        disk_byte=bmp_byte(i,(lba-2088-i*cluster_spacing)*512+offset);
            end
        end
    endfunction
    reg sector_busy=0,sector_valid=0,sector_done=0;
    reg [7:0] sector_data=0;
    reg [8:0] sector_index=0;
    integer model_state=0,model_index=0,model_delay=0,model_lba=0;
    integer file_reads [0:9];
    integer image_sectors [0:9];
    integer cancel_count=0,partial_cancel_count=0;
    reg cancelled_old=0;
    initial begin
        force dut.init_done=ready;
        force dut.card_ready=1;
        force dut.card_error=0;
        force dut.card_sector_busy=sector_busy;
        force dut.card_sector_valid=sector_valid;
        force dut.card_sector_done=sector_done;
        force dut.sector_data=sector_data;
        force dut.sector_index=sector_index;
    end
    always @(posedge clk) begin
        sector_valid<=0;sector_done<=0;
        if(!rst_n) begin model_state<=0;sector_busy<=0; end
        else case(model_state)
            0:if(dut.card_sector_req) begin
                model_lba<=dut.card_sector_lba;model_index<=0;sector_busy<=1;
                model_delay<=sector_delay_cycles!=0 ? sector_delay_cycles : subtitle_value && dut.card_sector_lba>=100078 ? 32 : dut.card_sector_lba>=2088 ?
                    (full_size ? 256 : image_scale_value ? 5000 : manual_priority_value ? 100000 : 10000) : 0;
                if(culture_priority_value && dut.card_sector_lba>=62088 && dut.card_sector_lba<62088+file_sectors)
                    model_delay<=20000;
                model_state<=1;sectors=sectors+1;
                for(integer i=0;i<10;i=i+1)
                    if(dut.card_sector_lba>=2088+i*cluster_spacing &&
                       dut.card_sector_lba<2088+i*cluster_spacing+file_sectors)begin
                        image_sectors[i]=image_sectors[i]+1;
                        if(dut.card_sector_lba==2088+i*cluster_spacing)file_reads[i]=file_reads[i]+1;
                    end
            end
            1:if(model_delay!=0) model_delay<=model_delay-1;
              else begin
                sector_valid<=1;sector_index<=model_index;sector_data<=disk_byte(model_lba,model_index);
                if(model_index==511) model_state<=2;else model_index<=model_index+1;
              end
            2:begin sector_busy<=0;sector_done<=1;model_state<=0; end
        endcase
        if(rst_n) begin
            cancelled_old<=dut.file_cancelled;
            if(dut.file_cancelled && !cancelled_old)begin
                cancel_count=cancel_count+1;
                if(dut.load_proc.fifo_count!=0)partial_cancel_count=partial_cancel_count+1;
                if(sector_busy || dut.sector_req)$fatal(1,"cancel acknowledged during an SD sector");
            end
            if(dut.fs_done && dut.file_cancelled && !dut.aux_active && dut.bank_complete[dut.load_bank])
                $fatal(1,"cancelled partial photo marked complete");
            if(dut.file_request && dut.load_proc.load_busy)$fatal(1,"reused a loading slot before drain");
            if(ready)begin
                refresh_gap=refresh_gap+1;
                if({ras_n,cas_n,we_n}==3'b001)begin
                    refresh_count=refresh_count+1;
                    if(refresh_gap>max_refresh_gap)max_refresh_gap=refresh_gap;
                    refresh_gap=0;
                end
                if(refresh_gap>2500)$fatal(1,"SDRAM periodic refresh deadline missed during image traffic");
            end
            if(wr_en && rd_en) $fatal(1,"simultaneous SDRAM clients");
            if(wr_en && arbiter.state!=1) $fatal(1,"SDRAM write outside granted transaction");
            if(rd_en && arbiter.state!=2) $fatal(1,"SDRAM read outside granted transaction");
            if(wr_en && display_ready && wr_addr/image_words==active_bank)
                $fatal(1,"overwriting displayed cache slot");
            if((ingest_error!=0 && !(all_bad && ingest_error==8'he6)) || reader_error!=0 || audio_error) begin
                $fdisplay(result_file,"FAIL ingest=%h reader=%h audio=%b source=%b pixel=%b state=%0d count=%0d/%0d",
                    ingest_error,reader_error,audio_error,audio_proc.source_error,audio_proc.pixel_error,
                    reader.state,reader.returned_count,reader.issued_count);
                $fclose(result_file);$fatal(1,"ten-image integration error");
            end
        end
    end
    reg [9:0] checked_images=0;
    integer video_pos=0;
    integer transition_pixels=0;
    reg [23:0] transition_expected;
    always @(negedge pix_clk) if(full_size && rst_n && audio_proc.linked_flag &&
        audio_proc.enable_sync[1] && display_ready && reader_error==0 && !underflow && !frame_ready &&
        !audio_proc.audio_enable) $fatal(1,"normal reader frame-prefetch gap muted/restarted audio");
    always @(negedge pix_clk) if(full_size) begin
        if(read_ack && display_ready) begin frame_image=active_index;video_check=1; end
        if(video_check && video_de) begin
            if(video_pos==0)begin
                transition_visible_index_q=frame_image;
                transition_visible_valid_q=1;
                if(active_source_width!==source_width_proc(frame_image) ||
                    active_source_height!==source_height_proc(frame_image))
                    $fatal(1,"source dimensions disagree with actual displayed image %0d",frame_image);
            end
            if(video_pos==2 && (audio_proc.image_index!=frame_image || !audio_proc.audio_enable))
                $fatal(1,"audio/video logical image mismatch image=%0d audio=%0d",frame_image,audio_proc.image_index);
            if(!frame_ready || underflow || video_pixel!==expected_pixel(frame_image,video_pos)) begin
                $fdisplay(result_file,"FAIL official video image=%0d pos=%0d pixel=%h expected=%h ready=%b underflow=%b",
                    frame_image,video_pos,video_pixel,expected_pixel(frame_image,video_pos),frame_ready,underflow);
                $fclose(result_file);$fatal(1,"official video pixel mismatch");
            end
            if(transition_mode_value!=0)begin
                transition_expected=video_pixel;
                if(transition_wipe_active && video_pos%640>=transition_wipe_ramp*40)
                    transition_expected=0;
                else if(transition_alpha!=255)begin
                    transition_expected[23:16]=(video_pixel[23:16]*int'(transition_alpha))/256;
                    transition_expected[15:8]=(video_pixel[15:8]*int'(transition_alpha))/256;
                    transition_expected[7:0]=(video_pixel[7:0]*int'(transition_alpha))/256;
                end
                if(transition_pixel!==transition_expected)$fatal(1,"effect pixel image=%0d pos=%0d got=%h exp=%h",
                    frame_image,video_pos,transition_pixel,transition_expected);
                if(transition_alpha!=255 || transition_wipe_active)transition_pixels=transition_pixels+1;
                if(video_pos==0 && frame_image==2 && !checked_images[2])begin
                    if(transition_mode_value==2 && (!transition_wipe_active || transition_wipe_ramp!=0))
                        $fatal(1,"new picture flashed before its first wipe frame");
                    if(transition_mode_value==1 && transition_alpha!=0)
                        $fatal(1,"new picture appeared before black-frame commit");
                end
            end
            video_pos=video_pos+1;
            if(video_pos==image_words) begin video_pos=0;frames=frames+1;checked_images[frame_image]=1; end
        end
    end
    initial begin
        wait(!full_size && rst_n && display_ready);
        forever begin
            repeat(1000) @(negedge pix_clk);
            frame_sync=0;read_req=1;
            wait(read_ack);@(negedge pix_clk);read_req=0;
            wait(frame_ready);repeat(4) @(negedge pix_clk);
            frame_image=active_index;
            transition_visible_index_q=frame_image;transition_visible_valid_q=1;
            if(!complete[active_bank]) $fatal(1,"displayed incomplete cache slot");
            for(integer pos=0;pos<image_words;pos=pos+1) begin
                read_en=1;@(posedge pix_clk);#1;
                if(pos==2 && (audio_proc.image_index!=frame_image || !audio_proc.audio_enable))
                    $fatal(1,"audio/video logical image mismatch image=%0d audio=%0d",frame_image,audio_proc.image_index);
                if(pixel!=={8'd0,expected_pixel(frame_image,pos)}) begin
                    $fdisplay(result_file,"FAIL frame image=%0d pos=%0d pixel=%h expected=%h",
                        frame_image,pos,pixel,expected_pixel(frame_image,pos));
                    $fclose(result_file);$fatal(1,"ten-image frame pixel mismatch");
                end
                @(negedge pix_clk);
            end
            read_en=0;checked_images[frame_image]=1;frames=frames+1;frame_sync=1;
        end
    end
    task automatic event_proc(input bit previous);
        begin
            @(negedge clk);next_down=!previous;prev_down=previous;
            @(negedge clk);next_down=0;prev_down=0;
        end
    endtask
    task automatic next_image(input integer target,input bit previous);
        time request_time,ready_time,visible_time,finish_time;
        reg [3:0] request_mask;
        begin
            request_time=$time;request_mask=complete;
            event_proc(previous);
            wait(requested_index==target && dut.target_ready);
            ready_time=$time;
            wait(transition_visible_valid && transition_visible_index==target);
            visible_time=$time;
            wait(active_index==target && !request_busy);
            finish_time=$time;
            wait(checked_images[target]);
            $fdisplay(result_file,"INFO manual PIC%0d: cache=%h ready=%0d ns, first target pixels=%0d ns, completed=%0d ns",
                target+1,request_mask,ready_time-request_time,visible_time-request_time,finish_time-request_time);
            if(group_prefetch_value && ready_time-request_time<200 && visible_time-request_time>33600000)
                $fatal(1,"resident manual request exceeded two official video frames");
        end
    endtask
    task automatic badge_event_proc(input [2:0] short_value,input [2:0] long_value);
        begin
            @(negedge clk);badge_short=short_value;badge_long=long_value;
            @(negedge clk);badge_short=0;badge_long=0;repeat(6)@(negedge clk);
        end
    endtask
    task automatic check_return_frame(input integer target);
        integer before_frames;
        begin
            wait(active_index==target && !request_busy);
            before_frames=frames;
            wait(frames>before_frames+1);
            if(active_index!=target || player_error!=0)$fatal(1,"badge returned to wrong page");
        end
    endtask
    task automatic exam_return_proc(input integer exam_state,input integer target);
        begin
            @(negedge clk);badge_exam=1;
            check_return_frame(8);wait(dut.cache_proc.state==7);
            if(exam_state!=2)begin
                badge_event_proc(1,0);
                if(!timer_running || timer_seconds!=60)$fatal(1,"return fixture failed to start 1min exam running=%b seconds=%0d",timer_running,timer_seconds);
                repeat(exam_state==1 ? 60000 : 1000)begin
                    @(negedge clk);tick_1ms=1;@(negedge clk);tick_1ms=0;
                end
            end
            repeat(8)@(negedge clk);
            if(timer_finished!=(exam_state==1))$fatal(1,"return fixture finish state");
            if(exam_state==2 && timer_running)$fatal(1,"return fixture unexpectedly started");
            @(negedge clk);badge_exam=0;
            check_return_frame(target);
            $fdisplay(result_file,"PASS exam %s returns to PIC%0d with exact pixels",
                exam_state==2 ? "ready" : exam_state==1 ? "finished" : "unfinished",target+1);
        end
    endtask
    task automatic scene_wait_proc(input integer target);
        integer timeout_tick;
        begin
            timeout_tick=0;
            while(active_index!=target || request_busy || transition_busy)begin
                @(negedge clk);timeout_tick=timeout_tick+1;
                if(timeout_tick==1000000)begin
                    $fdisplay(result_file,"FAIL scene=%0d group=%0d active=%0d requested=%0d display=%0d busy=%b fx=%b target_ready=%b cache_state=%0d search=%b consume=%b pixel_state=%0d",
                        badge_scene,badge_group,active_index,requested_index,display_index,request_busy,
                        transition_busy,target_ready,dut.cache_proc.state,player.search_flag,
                        badge_consume,transition_proc.pixel_state);
                    $fclose(result_file);$fatal(1,"scene switch stalled on PIC%0d",active_index+1);
                end
            end
            wait(checked_images[target]);
        end
    endtask
    task automatic scene_switch_proc;
        integer target;
        begin
            scene_wait_proc(1);
            for(integer group_index=0;group_index<3;group_index=group_index+1)begin
                if(group_index==1)badge_event_proc(0,1);
                if(group_index==2)badge_event_proc(0,2);
                target=group_index==0 ? 1 : group_index==1 ? 4 : 0;
                scene_wait_proc(target);
                for(integer phase=0;phase<12;phase=phase+1)begin
                    @(negedge clk);badge_exam=1;
                    if(phase<4)repeat(phase*1024+2)@(negedge clk);
                    else scene_wait_proc(8);
                    repeat(phase*13+1)@(negedge clk);
                    if(timer_running || timer_finished)$fatal(1,"exam not in ready state");
                    badge_exam=0;
                    scene_wait_proc(target);
                    $fdisplay(result_file,"PASS ready exam return group=%0d phase=%0d FX=%0d",group_index,phase,transition_mode_value);
                end
                @(negedge clk);badge_exam=1;scene_wait_proc(8);
                @(negedge clk);badge_fire=1;scene_wait_proc(9);
                @(negedge clk);badge_fire=0;scene_wait_proc(8);
                @(negedge clk);badge_exam=0;scene_wait_proc(target);
                if(group_index<2)begin
                    badge_event_proc(2,0);
                    wait(requested_index!=target);
                    if(transition_mode_value!=0)
                        wait(transition_proc.pixel_state==(transition_mode_value==1 ? 1 : 5));
                    @(negedge clk);badge_fire=1;scene_wait_proc(9);
                    @(negedge clk);badge_fire=0;scene_wait_proc(target);
                end
            end
            $fdisplay(result_file,"PASS %s",test_name);$fclose(result_file);$finish;
        end
    endtask
    task automatic priority_image_proc(input integer target,input integer stale,input bit previous);
        integer stale_sectors,target_reads,timeout_tick;
        time request_time;
        begin
            wait(dut.cache_proc.state==6 && dut.cache_proc.file_index==stale &&
                model_state==1 && model_lba>=2088+stale*cluster_spacing &&
                model_lba<2088+stale*cluster_spacing+file_sectors &&
                (!image_scale_value || dut.load_proc.fifo_count!=0));
            stale_sectors=image_sectors[stale];target_reads=file_reads[target];request_time=$time;
            event_proc(previous);
            timeout_tick=0;
            while(file_reads[target]==target_reads)begin
                @(negedge clk);timeout_tick=timeout_tick+1;
                if(image_sectors[stale]>stale_sectors+1)
                    $fatal(1,"manual PIC%0d waited behind unrelated PIC%0d sectors",target+1,stale+1);
                if(timeout_tick==200000)$fatal(1,"manual target did not preempt unrelated file");
            end
            $fdisplay(result_file,"INFO cold manual PIC%0d starts after %0d ns; unrelated extra data sectors=%0d",
                target+1,$time-request_time,image_sectors[stale]-stale_sectors);
            wait(active_index==target && !request_busy && !transition_busy);
            wait(checked_images[target]);
            if(valid_mask!=10'h3ff)$fatal(1,"preemption invalidated a good photo");
        end
    endtask
    task automatic manual_priority_proc;
        integer before_reads;
        begin
            wait(checked_images[1]);wait(!request_busy);
            priority_image_proc(3,2,1);
            wait(dut.cache_proc.state==6 && dut.cache_proc.file_index==2);
            before_reads=file_reads[2];
            next_image(1,0);
            wait(dut.cache_proc.state==7);
            if(file_reads[2]!=before_reads)$fatal(1,"resident hit restarted unrelated prefetch");
            before_reads=sectors;
            next_image(2,0);next_image(1,1);
            if(sectors!=before_reads)$fatal(1,"warm manual navigation read TF again");
            @(negedge clk);group_selection=10'h0f0;group_target_index=4;group_target_valid=1;
            @(negedge clk);group_target_valid=0;
            wait(active_index==4 && !request_busy && !transition_busy);wait(checked_images[4]);
            priority_image_proc(7,5,1);
            wait(dut.cache_proc.state==7);
            before_reads=sectors;
            next_image(4,0);next_image(5,0);next_image(6,0);next_image(5,1);
            if(sectors!=before_reads)$fatal(1,"filled culture group read TF on manual navigation");
            if(cancel_count<2 || partial_cancel_count<1)$fatal(1,"cancellation drain coverage incomplete");
            $fdisplay(result_file,"PASS cold manual targets start before unrelated prefetch completes; warm hits do not abort files; exact frame pixels; cancels=%0d partial FIFO drains=%0d refresh max=%0d cycles",
                cancel_count,partial_cancel_count,max_refresh_gap);
            $fdisplay(result_file,"PASS %s",test_name);$fclose(result_file);$finish;
        end
    endtask
    initial begin
        test_name=startup_only ? (culture_priority_value ? "tb_photo_culture_full_pipeline" : font_cache_value>=2 ? "tb_photo_font_service_pipeline" : "tb_photo_startup_subtitle") : image_scale_value ? (image_scale_value==2 ? "tb_photo_image_scale_cancel" :
            image_scale_value==3 ? "tb_photo_image_scale_faults" : wav_value ? "tb_photo_image_scale_wav_full" :
            full_size ? "tb_photo_image_scale_pipeline_full" : "tb_photo_image_scale_pipeline") :
            wav_value ? "tb_photo_wav_full" : subtitle_service_value ? "tb_photo_subtitle_manual" :
            subtitle_value ? (full_size ? "tb_photo_subtitle_full" : $sformatf("tb_photo_subtitle_fat_%0d",subtitle_value)) :
            manual_priority_value ? (full_size ? "tb_photo_manual_priority_full" :
            $sformatf("tb_photo_manual_priority_%0d",transition_mode_value)) :
            scene_switch_value ? $sformatf("tb_photo_scene_switch_%0d",transition_mode_value) :
            group_prefetch_value ? (full_size ? "tb_photo_group_full" : "tb_photo_group") :
            transition_mode_value==1 ? "tb_photo_ten_transition_full_fade" :
            transition_mode_value==2 ? "tb_photo_ten_transition_full_wipe" :
            badge_return ? (full_size ? "tb_photo_exam_return_full" : "tb_photo_exam_return") :
            scene_audio ? (full_size ? "tb_photo_ten_scene_full" : "tb_photo_ten_scene") :
            full_size ? "tb_photo_ten_full" : all_bad ? "tb_photo_ten_all_bad" :
            bad_first ? "tb_photo_ten_bad_first" : "tb_photo_ten";
        result_file=$fopen({test_name,".result"},"w");
        for(integer i=0;i<10;i=i+1)begin file_reads[i]=0;image_sectors[i]=0;end
        repeat(8) @(negedge clk);rst_n=1;
        if(all_bad) begin
            wait(ingest_error==8'he6);
            if(display_ready || complete!=0 || valid_mask!=0) $fatal(1,"all-bad card exposed a frame");
            $fdisplay(result_file,"PASS all ten bad files produce E6 without a committed cache slot");
            $fdisplay(result_file,"PASS tb_photo_ten_all_bad");$fclose(result_file);$finish;
        end
        wait(display_ready);
        if(startup_only)wait(1'b0);
        if(image_scale_value)begin
            if(image_scale_value==2)manual_priority_proc();
            if(image_scale_value==3)begin
                wait(checked_images[1]);wait(dut.cache_proc.state==7);
                if(valid_mask[2] || valid_mask[3] || active_index!=1 || file_reads[2]!=1 || file_reads[3]!=1)
                    $fatal(1,"malformed scaled images were published or retried");
                @(negedge clk);group_selection=10'h0f0;group_target_index=4;group_target_valid=1;
                @(negedge clk);group_target_valid=0;wait(checked_images[5]);wait(dut.cache_proc.state==7);
                if(valid_mask[4] || valid_mask[6])$fatal(1,"bad scaled dimensions or truncated source accepted");
                next_image(7,0);next_image(5,1);
                if(ingest_error || reader_error)$fatal(1,"bad scaled source poisoned a valid frame");
                $fdisplay(result_file,"PASS bad dimensions/BPP/compression/truncation skip once; previous complete frame survives; good scaled images remain usable");
                $fdisplay(result_file,"PASS %s",test_name);$fclose(result_file);$finish;
            end
            wait(checked_images[1]);next_image(2,0);next_image(3,0);next_image(1,0);
            @(negedge clk);group_selection=10'h0f0;group_target_index=4;group_target_valid=1;
            @(negedge clk);group_target_valid=0;wait(checked_images[4]);
            next_image(5,0);next_image(6,0);next_image(7,0);next_image(4,0);
            wait(dut.cache_proc.state==7);
            begin
                integer before_reads;
                before_reads=image_sectors[4]+image_sectors[5]+image_sectors[6]+image_sectors[7];
                next_image(7,1);next_image(4,0);
                if(image_sectors[4]+image_sectors[5]+image_sectors[6]+image_sectors[7]!=before_reads)
                    $fatal(1,"scaled warm frames read TF again");
            end
            if(wav_value)begin
                wait(subtitle_ready);wait(wav_samples>=8000);
                if(wav_error || subtitle_error)$fatal(1,"scaled loading disturbed WAV/subtitles");
            end
            if(ingest_error || reader_error || refresh_count<10 || max_refresh_gap>2500)
                $fatal(1,"scaled image integration error");
            $fdisplay(result_file,"PASS mixed aspect ratios, odd row padding, both BMP orientations, up/down scaling, exact SDRAM/video pixels and warm-cache flips");
            $fdisplay(result_file,"PASS refresh max=%0d cycles, ordered PCM samples=%0d",max_refresh_gap,wav_samples);
            $fdisplay(result_file,"PASS %s",test_name);$fclose(result_file);$finish;
        end
        if(wav_value)begin
            integer paused_samples;
            wait(checked_images[1]);next_image(2,0);
            @(negedge clk);group_selection=10'h0f0;group_target_index=4;group_target_valid=1;
            @(negedge clk);group_target_valid=0;wait(checked_images[4]);
            wait(wav_samples>=2000);wav_scene=2;repeat(40)@(negedge pix_clk);paused_samples=wav_samples;
            repeat(20000)@(negedge pix_clk);if(wav_samples!=paused_samples)$fatal(1,"fire consumed ordinary WAV");
            wav_scene=0;next_image(5,0);next_image(4,1);wait(wav_samples>=8000);
            if(wav_error || subtitle_error || reader_error || refresh_count<100 || max_refresh_gap>2500)$fatal(1,"full WAV regressions");
            $fdisplay(result_file,"PASS 640x480 exact image/subtitle pixels with two FAT cursors and one shared SD service, fragmented WAV, 8000 ordered PCM samples, fire pause/resume");
            $fdisplay(result_file,"PASS periodic refresh max=%0d cycles; cold group and resident bidirectional flips",max_refresh_gap);
            $fdisplay(result_file,"PASS tb_photo_wav_full");$fclose(result_file);$finish;
        end
        if(subtitle_value)begin
            integer before_sectors;
            if(subtitle_value==1)begin
                wait(dut.aux_active && subtitle_index==0 && sector_busy);
                @(negedge clk);group_selection=10'h0f0;group_target_index=4;group_target_valid=1;
                @(negedge clk);group_target_valid=0;
                wait(subtitle_cancelled);subtitle_cancels=subtitle_cancels+1;
                wait(active_index==4 && !request_busy);wait(checked_images[4]);
            end else begin wait(checked_images[1]);wait(!request_busy);end
            wait(subtitle_ready || subtitle_error);
            if(subtitle_value==1 && (subtitle_error!=0 || subtitle_notice_length!=21 || subtitle_teacher_length!=20))
                $fatal(1,"FAT subtitle failed ready=%b error=%h length=%0d/%0d",subtitle_ready,subtitle_error,subtitle_notice_length,subtitle_teacher_length);
            if(subtitle_value==2 && subtitle_error!=8'h81)$fatal(1,"missing TXT not isolated");
            if(subtitle_value==3 && subtitle_error!=8'h87)$fatal(1,"unsupported glyph not isolated");
            wait(dut.cache_proc.state==7);wait(!dut.fs_busy);before_sectors=sectors;
            if(subtitle_value==1)begin next_image(5,0);next_image(4,1);end
            else begin next_image(2,0);next_image(1,1);end
            repeat(2000)@(negedge clk);
            if(sectors!=before_sectors || ingest_error!=0 || reader_error!=0)$fatal(1,"subtitle disturbed warm pictures or kept reading TF");
            if(full_size && subtitle_checked_pixels<100)$fatal(1,"full subtitle overlay not exercised");
            $fdisplay(result_file,"PASS shared FAT32 TXT files/internal font, image preemption/retry=%0d, 21/20 UTF-8, missing/unsupported isolation, exact image pixels, idle TF stop, refresh max=%0d",subtitle_cancels,max_refresh_gap);
            $fdisplay(result_file,"PASS %s",test_name);$fclose(result_file);$finish;
        end
        if(manual_priority_value)manual_priority_proc();
        if(scene_switch_value)scene_switch_proc();
        if(group_prefetch_value)begin
            integer before_sectors;
            wait(checked_images[1]);
            next_image(3,1);
            wait(dut.cache_proc.state==7);
            before_sectors=sectors;
            next_image(1,0);next_image(2,0);next_image(1,1);
            if(sectors!=before_sectors || file_reads[0] || file_reads[1]!=1 ||
               file_reads[2]!=1+cancel_count || file_reads[3]!=1)
                $fatal(1,"notice manual navigation caused extra file reads");
            @(negedge clk);group_selection=10'h0f0;group_target_index=4;group_target_valid=1;
            @(negedge clk);group_target_valid=0;
            wait(active_index==4 && !request_busy);wait(checked_images[4]);wait(dut.cache_proc.state==7);
            before_sectors=sectors;
            next_image(7,1);next_image(4,0);next_image(5,0);next_image(6,0);
            if(sectors!=before_sectors || file_reads[4]!=1 || file_reads[5]!=1 || file_reads[6]!=1 || file_reads[7]!=1)
                $fatal(1,"culture group did not remain resident");
            $fdisplay(result_file,"PASS group prefetch with real SDRAM/video: cold previous request, notice/culture bidirectional wrap without TF reads; resident first pixels within two frames");
            $fdisplay(result_file,"PASS refresh commands=%0d maximum gap=%0d cycles",refresh_count,max_refresh_gap);
            $fdisplay(result_file,"PASS %s",test_name);$fclose(result_file);$finish;
        end
        if(badge_return)begin
            check_return_frame(1);
            @(negedge clk);badge_config_apply=1;@(negedge clk);badge_config_apply=0;
            repeat(8)@(negedge clk);
            exam_return_proc(2,1);exam_return_proc(0,1);exam_return_proc(1,1);
            badge_event_proc(0,2);check_return_frame(0);
            exam_return_proc(2,0);exam_return_proc(0,0);exam_return_proc(1,0);
            badge_event_proc(0,2);check_return_frame(1);
            if(refresh_count<10)$fatal(1,"exam return did not exercise periodic refresh");
            $fdisplay(result_file,"PASS periodic refresh with image reads/writes: commands=%0d maximum gap=%0d cycles",refresh_count,max_refresh_gap);
            $fdisplay(result_file,"%s",full_size ? "PASS tb_photo_exam_return_full" : "PASS tb_photo_exam_return");
            $fclose(result_file);$finish;
        end
        if(checked_images!=0 || dut.cache_proc.cache_valid==4'hf)
            $fatal(1,"first image waited for cache fill");
        if(bad_first) begin
            wait(checked_images[2]);
            if(valid_mask[0] || valid_mask[1] || active_index!=2) $fatal(1,"first surviving image selection failed");
            $fdisplay(result_file,"PASS bad first/second files skipped before first complete frame");
            $fdisplay(result_file,"PASS tb_photo_ten_bad_first");$fclose(result_file);$finish;
        end
        wait(checked_images[0]);
        if(full_size) begin
            next_image(2,0);
            if(audio_sample_count<1000 || audio_acr_count<10) $fatal(1,"full-size PCM/ACR coverage incomplete");
            $fdisplay(result_file,"PASS 640x480 early display and background loading through official SDRAM core");
            $fdisplay(result_file,"PASS full-size slot protection, all pixels, bad-file early stop and cache miss");
            $fdisplay(result_file,"PASS continuous PCM/ACR and logical-image audio commit at official visible frame");
            if(transition_mode_value!=0)begin
                if(transition_pixels<640*480*15)$fatal(1,"effect frames were not exercised");
                $fdisplay(result_file,"PASS real overlay every-pixel transition comparison, no first-frame flash, effect pixels=%0d",transition_pixels);
            end
            $fdisplay(result_file,"PASS %s",test_name);
            $fclose(result_file);$finish;
        end
        next_image(2,0); next_image(3,0); next_image(4,0); next_image(5,0);
        next_image(7,0); next_image(8,0); next_image(9,0); next_image(0,0);next_image(9,1);
        if(checked_images!=10'h3bd || valid_mask!=10'h3bd || file_reads[1]!=1 || file_reads[6]!=1)
            $fatal(1,"ten-image masks/retry counts checked=%h valid=%h bad=%0d/%0d",
                checked_images,valid_mask,file_reads[1],file_reads[6]);
        @(negedge clk);auto_down=1;@(negedge clk);auto_down=0;
        repeat(8) begin
            integer previous_index;
            previous_index=active_index;
            repeat(3) begin @(negedge clk);tick_1ms=1;@(negedge clk);tick_1ms=0; end
            wait(active_index!=previous_index && !request_busy);
            if(player_error!=0 || !valid_mask[active_index]) $fatal(1,"automatic bad-file skip failed");
        end
        @(negedge clk);auto_down=1;@(negedge clk);auto_down=0;
        begin
            integer before_sectors;
            wait(dut.cache_proc.state==7);
            before_sectors=sectors;repeat(20000) @(negedge clk);
            if(sectors!=before_sectors) $fatal(1,"idle cache keeps reading TF");
        end
        $fdisplay(result_file,"PASS ten filenames including PIC10 at final directory slot, eight good frames");
        $fdisplay(result_file,"PASS first complete frame starts early, real encrypted SDRAM controller and four-slot ring");
        $fdisplay(result_file,"PASS large/small bad files tried once, immediate invalid-target skip, forward/backward wrap and idle TF stop");
        if(audio_sample_count<10 || audio_acr_count<1) $fatal(1,"ten-image PCM/ACR coverage incomplete");
        $fdisplay(result_file,"PASS logical PIC1-PIC10 audio handshake across cache eviction, wraps and automatic playback");
        $fdisplay(result_file,"%s",scene_audio ? "PASS tb_photo_ten_scene" : "PASS tb_photo_ten");
        $fclose(result_file);$finish;
    end
    initial begin #(full_size ? 2000000000 : (image_scale_value || scene_switch_value || manual_priority_value || subtitle_value) ? 500000000 : 20000000);
        $fdisplay(result_file,"FAIL watchdog cache=%0d fs=%0d active=%0d valid=%h requested=%0d player=%h checked=%h frames=%0d display=%b req=%b ack=%b reader=%0d count=%0d/%0d arb=%0d prefetch=%b ready=%b armed=%b clear=%b",
            dut.cache_proc.state,dut.fs_proc.state,active_index,valid_mask,requested_index,player_error,
            checked_images,frames,display_ready,read_req,read_ack,reader.state,reader.returned_count,reader.issued_count,
            arbiter.state,reader.prefetch_mem,frame_ready,reader.pixel_armed,reader.fifo_clear);
        $fclose(result_file);$fatal(1,"ten-image watchdog"); end
endmodule
