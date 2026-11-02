`timescale 1ns/1ps
module top (
    input wire clk, input wire rst_n, input wire key1, input wire key2,
    input wire key3, input wire sw1, input wire sw2, input wire sw3, input wire sw4,
    output wire [5:0] seg_sel, output wire [7:0] seg_data,
    output wire HDMI_CLK_P, output wire HDMI_D2_P,
    output wire HDMI_D1_P, output wire HDMI_D0_P,
    output wire HDMI_DDC_SCL, inout wire HDMI_DDC_SDA,
    output wire sd_ncs, output wire sd_dclk, output wire sd_mosi, input wire sd_miso,
    input wire flash_miso, output wire flash_cs_n, output wire flash_sclk,
    output wire flash_mosi, output wire flash_wp_n, output wire flash_hold_n
);
    wire sd_card_clk, ext_mem_clk, ext_mem_clk_sft, video_clk, hdmi_5x_clk;
    wire audio_pll_lock, audio_mclk;
    reg [15:0] startup_reset_buf=16'hffff;
    always @(posedge clk or negedge audio_pll_lock)begin
        if(!audio_pll_lock)startup_reset_buf<=16'hffff;
        else startup_reset_buf<={startup_reset_buf[14:0],1'b0};
    end
    wire rst_all = startup_reset_buf[15] | ~audio_pll_lock;
    wire system_rst_n,mem_rst_n,pix_rst_n;
    sys_pll sys_pll_m0 (
        .refclk(clk), .clk0_out(sd_card_clk), .clk1_out(ext_mem_clk),
        .clk2_out(ext_mem_clk_sft), .reset(1'b0)
    );
    video_pll video_pll_m0 (
        .refclk(clk), .clk0_out(video_clk), .clk1_out(hdmi_5x_clk), .reset(1'b0)
    );
    PLL_HDMI_AUDIO u_audio_pll (
        .refclk(clk), .reset(1'b0), .extlock(audio_pll_lock),
        .clk0_out(), .clk1_out(), .clk2_out(audio_mclk)
    );
    photo_reset_sync mem_reset_proc (.clk(ext_mem_clk),.reset_req(rst_all),.rst_n(mem_rst_n));
    photo_reset_sync pix_reset_proc (.clk(video_clk),.reset_req(rst_all),.rst_n(pix_rst_n));
    photo_reset_sync system_reset_proc (.clk(clk),.reset_req(rst_all),.rst_n(system_rst_n));
    wire controller_ready, controller_busy, refresh_active;
    wire app_wr_en, app_rd_en, sdram_rd_valid;
    wire [20:0] app_wr_addr, app_rd_addr;
    wire [31:0] app_wr_data, sdram_rd_data;
    wire [3:0] app_wr_mask, image_complete, status_code;
    wire [7:0] error_code, error_detail, read_error;
    wire display_ready, underflow_flag, audio_error;
    wire target_ready, display_publish_enable, transition_busy;
    wire [7:0] transition_alpha;
    wire transition_wipe_active, overlay_frame_start, overlay_visible_valid, overlay_scene_visible;
    wire overlay_visible_frame_pulse,hdmi_video_locked;
    wire [4:0] transition_wipe_ramp;
    wire [3:0] overlay_visible_index, overlay_incoming_index;
    wire overlay_incoming_valid;
    wire write_request, write_grant, write_done, read_request, read_grant, read_done, refresh_request;
    wire [9:0] valid_mask, selection_mask;
    wire [3:0] requested_index, display_index, active_index;
    wire [11:0] active_source_width,active_source_height;
    wire [11:0] visible_source_width,visible_source_height;
    reg startup_image_latched;
    wire [3:0] ingest_requested_index = startup_image_latched ? requested_index : 4'd1;
    wire [1:0] display_bank, active_bank;
    wire [15:0] startup_detail;
    wire auto_mode, request_busy, frame_commit;
    wire key1_short_event,resolution_notice;
    wire [1:0] badge_scene_mode;
    wire auto_notice,manual_notice,wav_ready,wav_consume;
    wire signed [15:0] wav_sample;
    wire [7:0] wav_error;
    wire subtitle_request,subtitle_done,subtitle_start,subtitle_valid,subtitle_end,subtitle_finished,subtitle_cancelled;
    wire [1:0] subtitle_index;
    wire [31:0] subtitle_size,subtitle_offset;
    wire [31:0] subtitle_range_offset;
    wire subtitle_close;
    wire [7:0] subtitle_data,subtitle_file_error,subtitle_load_error,subtitle_error;
    wire subtitle_ready,subtitle_mem_en,subtitle_mem_write_en,subtitle_enable;
    wire [2:0] subtitle_speed,subtitle_alpha;
    wire [10:0] subtitle_mem_addr;
    wire [15:0] subtitle_mem_write_data,subtitle_mem_read_data;
    wire [4:0] subtitle_notice_length,subtitle_teacher_length;
    photo_memory_arbiter memory_proc (
        .clk(ext_mem_clk),.rst_n(mem_rst_n),.controller_ready(controller_ready),
        .controller_busy(controller_busy),.refresh_active(refresh_active),
        .write_request(write_request),.read_request(read_request),
        .write_done(write_done),.read_done(read_done),.write_grant(write_grant),.read_grant(read_grant),
        .refresh_request(refresh_request)
    );
    photo_ingest #(.group_prefetch(1),.subtitle_support(1),.wav_support(1),.image_scale_support(1)) ingest_proc (
        .clk(ext_mem_clk),.rst_n(mem_rst_n),.controller_ready(controller_ready),
        .controller_busy(controller_busy),.refresh_active(refresh_active),
        .requested_index(ingest_requested_index),.active_bank(active_bank),.auto_mode(auto_mode),
        .display_publish_enable(display_publish_enable),
        .wav_play_enable(badge_scene_mode==0),.wav_pix_clk(video_clk),.wav_pix_rst_n(pix_rst_n),
        .wav_consume(wav_consume),.wav_sample(wav_sample),.wav_ready(wav_ready),.wav_error(wav_error),
        .selection_mask(selection_mask),
        .memory_grant(write_grant),.memory_request(write_request),.memory_done(write_done),
        .display_bank(display_bank),.active_index(active_index),.display_index(display_index),.valid_mask(valid_mask),
        .active_source_width(active_source_width),.active_source_height(active_source_height),
        .display_ready(display_ready),.target_ready(target_ready),.status_code(status_code),
        .error_code(error_code),.error_detail(error_detail),.image_complete(image_complete),
        .startup_detail(startup_detail),
        .subtitle_request(subtitle_request),.subtitle_index(subtitle_index),.subtitle_done(subtitle_done),
        .subtitle_range_offset(subtitle_range_offset),.subtitle_close(subtitle_close),
        .subtitle_service_complete(subtitle_ready || subtitle_error!=0),
        .subtitle_load_error(subtitle_load_error),.subtitle_start(subtitle_start),.subtitle_valid(subtitle_valid),
        .subtitle_end(subtitle_end),.subtitle_finished(subtitle_finished),.subtitle_cancelled(subtitle_cancelled),
        .subtitle_size(subtitle_size),.subtitle_offset(subtitle_offset),.subtitle_data(subtitle_data),
        .subtitle_file_error(subtitle_file_error),
        .app_wr_en(app_wr_en),.app_wr_addr(app_wr_addr),.app_wr_data(app_wr_data),
        .app_wr_mask(app_wr_mask),.sd_cs_n(sd_ncs),.sd_sclk(sd_dclk),
        .sd_mosi(sd_mosi),.sd_miso(sd_miso)
    );
    photo_subtitle_load #(.external_font(1)) subtitle_load_proc(
        .clk(ext_mem_clk),.rst_n(mem_rst_n),.enable(display_ready),
        .file_request(subtitle_request),.file_index(subtitle_index),
        .range_offset(subtitle_range_offset),.file_close(subtitle_close),
        .file_start(subtitle_start),.file_valid(subtitle_valid),.file_end(subtitle_end),
        .file_finished(subtitle_finished),.file_cancelled(subtitle_cancelled),
        .file_size(subtitle_size),.file_offset(subtitle_offset),.file_data(subtitle_data),.file_error(subtitle_file_error),
        .load_done(subtitle_done),.load_error(subtitle_load_error),.ready(subtitle_ready),.error_code(subtitle_error),
        .notice_length(subtitle_notice_length),.teacher_length(subtitle_teacher_length),
        .mem_en(subtitle_mem_en),.mem_write_en(subtitle_mem_write_en),.mem_addr(subtitle_mem_addr),
        .mem_write_data(subtitle_mem_write_data),.mem_read_data(subtitle_mem_read_data));
    photo_sdram U3 (
        .clk(ext_mem_clk),.clk_sft(ext_mem_clk_sft),.reset_req(rst_all),.refresh_request(refresh_request),
        .controller_ready(controller_ready),.refresh_active(refresh_active),.controller_busy(controller_busy),
        .app_wr_en(app_wr_en),.app_wr_addr(app_wr_addr),.app_wr_mask(app_wr_mask),.app_wr_data(app_wr_data),
        .app_rd_en(app_rd_en),.app_rd_addr(app_rd_addr),
        .sdram_rd_valid(sdram_rd_valid),.sdram_rd_data(sdram_rd_data)
    );
    wire video_read_req, video_read_req_ack, video_read_en;
    wire [31:0] video_read_data;
    wire hs_0, vs_0, de_0, hs, vs, de;
    wire [23:0] vout_data_raw, vout_data;
    wire tick_1ms, next_down, auto_step, prev_down;
    wire [7:0] player_error;
    wire player_enable = display_ready && read_error == 0;
    wire [2:0] badge_short_event, badge_long_event;
    wire exam_request, fire_request, music_mute, music_enable;
    wire [1:0] badge_page_group;
    wire [2:0] badge_menu_item;
    wire [1:0] eye_mode, transition_mode;

    wire badge_menu_active, badge_temporary_pause, badge_consume_event;
    wire badge_page_select_valid;
    wire [3:0] badge_page_select_index;
    wire [1:0] badge_menu_adjust;
    wire exam_start_toggle, exam_duration_step, exam_reset;
    wire badge_page_change, badge_page_return_valid, exam_pause, exam_finish;
    wire exam_started, exam_running, exam_finished;
    wire [3:0] badge_page_return_index;
    wire [2:0] music_volume, brightness_level, exam_duration_index;
    wire [15:0] slideshow_ms;
    wire [4:0] slideshow_seconds;
    wire config_apply, config_ready, config_busy, config_saved;
    reg [9:0] save_notice_ms;
    always @(posedge ext_mem_clk or negedge mem_rst_n)begin
        if(!mem_rst_n)save_notice_ms<=0;
        else if(config_saved)save_notice_ms<=10'd1000;
        else if(tick_1ms && save_notice_ms!=0)save_notice_ms<=save_notice_ms-1'b1;
    end
    wire [3:0] save_status=config_busy ? 4'd1 : save_notice_ms!=0 ? 4'd2 : 4'd0;
    wire [25:0] config_data;
    wire [7:0] config_error;
    photo_config_flash config_proc (
        .clk(ext_mem_clk),.rst_n(mem_rst_n),.tick_1ms(tick_1ms),.menu_active(badge_menu_active),
        .live_data({subtitle_alpha,subtitle_speed,subtitle_enable,transition_mode,1'b0,eye_mode,exam_duration_index,slideshow_seconds,brightness_level,music_volume}),
        .config_apply(config_apply),.config_data(config_data),.ready(config_ready),
        .busy(config_busy),.saved(config_saved),.error_code(config_error),
        .flash_cs_n(flash_cs_n),.flash_sclk(flash_sclk),.flash_mosi(flash_mosi),
        .flash_miso(flash_miso),.flash_wp_n(flash_wp_n),.flash_hold_n(flash_hold_n)
    );
    wire [31:0] exam_remaining_seconds;
    wire [15:0] exam_remaining_minutes;
    wire [5:0] exam_remaining_second;
    wire exam_timer_running, exam_timer_finished;
    assign selection_mask = badge_scene_mode==2'd2 ? 10'b1000000000 :
                                 badge_scene_mode==2'd1 ? 10'b0100000000 :
                                 badge_page_group==2'd2 ? 10'b0000000001 :
                                 badge_page_group==2'd1 ? 10'b0011110000 : 10'b0000001110;
    always @(posedge ext_mem_clk or negedge mem_rst_n) begin
        if (!mem_rst_n)
            startup_image_latched <= 1'b0;
        else if (display_ready)
            startup_image_latched <= 1'b1;
    end
    photo_badge_input badge_input_proc (
        .clk(ext_mem_clk),.rst_n(mem_rst_n),.enable(player_enable),.consume(badge_consume_event),
        .key1_n(rst_n),.key2_n(key1),.key3_n(key3),.key4_n(key2),
        .sw1(sw1),.sw3(sw3),.sw4(sw4),
        .tick_1ms(tick_1ms),.key1_short_event(key1_short_event),
        .short_event(badge_short_event),.long_event(badge_long_event),
        .music_mute(music_mute),.exam_request(exam_request),.fire_request(fire_request)
    );
    photo_badge_control badge_control_proc (
        .clk(ext_mem_clk),.rst_n(mem_rst_n),.enable(player_enable),.tick_1ms(tick_1ms),
        .short_event(badge_short_event),.long_event(badge_long_event),.key1_short_event(key1_short_event),
        .exam_request(exam_request),.fire_request(fire_request),.music_mute(music_mute),
        .player_busy(request_busy || transition_busy),.frame_commit(frame_commit),.active_index(active_index),.exam_done(exam_timer_finished),
        .config_apply(config_apply),.config_data(config_data),
        .player_next_down(next_down),.player_prev_down(prev_down),.player_auto_step(auto_step),.auto_mode(auto_mode),
         .consume_event(badge_consume_event),.temporary_pause(badge_temporary_pause),.auto_notice(auto_notice),.manual_notice(manual_notice),
        .page_group(badge_page_group),.page_change(badge_page_change),
        .page_return_index(badge_page_return_index),.page_return_valid(badge_page_return_valid),
        .page_select_valid(badge_page_select_valid),.page_select_index(badge_page_select_index),
        .menu_active(badge_menu_active),
        .menu_item(badge_menu_item),.menu_adjust(badge_menu_adjust),
        .music_volume(music_volume),.brightness_level(brightness_level),.slideshow_ms(slideshow_ms),
        .eye_mode(eye_mode),.transition_mode(transition_mode),
        .subtitle_enable(subtitle_enable),.subtitle_speed(subtitle_speed),.subtitle_alpha(subtitle_alpha),
        .resolution_notice(resolution_notice),
        .slideshow_seconds(slideshow_seconds),
        .exam_start_toggle(exam_start_toggle),.exam_duration_step(exam_duration_step),
        .exam_reset(exam_reset),.exam_pause(exam_pause),.exam_finish(exam_finish),
        .exam_started(exam_started),.exam_running(exam_running),.exam_finished(exam_finished),
        .exam_duration_index(exam_duration_index),.music_enable(music_enable),.scene_mode(badge_scene_mode)
    );
    photo_exam_timer exam_timer_proc (
        .clk(ext_mem_clk),.rst_n(mem_rst_n),.tick_1ms(tick_1ms),
        .exam_enable(exam_request),.pause_active(fire_request),.start_toggle(exam_start_toggle),
        .duration_step(exam_duration_step),.reset_cmd(exam_reset),.pause_cmd(exam_pause),
        .duration_index(exam_duration_index),.remaining_seconds(exam_remaining_seconds),
        .remaining_minutes(exam_remaining_minutes),.remaining_second(exam_remaining_second),
        .running(exam_timer_running),.finished(exam_timer_finished)
    );
    photo_player_control #(.image_count(10),.external_control(1)) player_proc (
        .clk(ext_mem_clk),.rst_n(mem_rst_n),.enable(player_enable),
        .tick_1ms(1'b0),.next_down(next_down),.auto_down(1'b0),.prev_down(prev_down),
        .external_auto(auto_mode),.auto_step(auto_step),.discard_events(badge_consume_event),
        .frame_commit(frame_commit && !transition_busy),.active_index(active_index),
        .valid_mask(valid_mask),
        .selection_mask(selection_mask),.target_valid(badge_page_select_valid),.target_index(badge_page_select_index),
        .image_index(requested_index),.auto_mode(),.request_busy(request_busy),.timer_en(),
        .error_code(player_error)
    );
    wire frame_ready;
    photo_frame_reader #(.arbitrated(1)) reader_proc (
        .mem_clk(ext_mem_clk),.mem_rst_n(mem_rst_n),.pix_clk(video_clk),.pix_rst_n(pix_rst_n),
        .display_ready(display_ready),.image_index(display_bank),
        .controller_ready(controller_ready),.controller_busy(controller_busy),.refresh_active(refresh_active),
        .memory_grant(read_grant),.memory_request(read_request),.memory_done(read_done),
        .app_rd_en(app_rd_en),.app_rd_addr(app_rd_addr),
        .sdram_rd_valid(sdram_rd_valid),.sdram_rd_data(sdram_rd_data),
        .frame_sync(vs_0),.read_req(video_read_req),.read_req_ack(video_read_req_ack),
        .read_en(video_read_en),.read_data(video_read_data),
        .underflow_flag(underflow_flag),.error_code(read_error),
        .frame_ready(frame_ready),
        .frame_commit(frame_commit),.active_index(active_bank)
    );
    photo_transition_control transition_proc (
        .mem_clk(ext_mem_clk),.mem_rst_n(mem_rst_n),
        .allow_transition(badge_scene_mode==0),.transition_mode(transition_mode),
        .display_ready(display_ready),.requested_index(ingest_requested_index),
        .display_index(display_index),.target_ready(target_ready),
        .display_publish_enable(display_publish_enable),.transition_busy(transition_busy),
        .pix_clk(video_clk),.pix_rst_n(pix_rst_n),.frame_start(overlay_frame_start),
        .incoming_valid(overlay_incoming_valid),.incoming_index(overlay_incoming_index),
        .visible_valid(overlay_visible_valid),.visible_index(overlay_visible_index),
        .background_alpha(transition_alpha),.wipe_active(transition_wipe_active),
        .wipe_ramp(transition_wipe_ramp)
    );
    video_timing_data video_timing_data_m0 (
        .video_clk(video_clk),.rst(rst_all),.read_req(video_read_req),
        .read_req_ack(video_read_req_ack),.hs(hs_0),.vs(vs_0),.de(de_0)
    );
    video_delay video_delay_m0 (
        .video_clk(video_clk),.rst(rst_all),.read_en(video_read_en),
        .read_data(video_read_data[23:0]),.hs(hs_0),.vs(vs_0),.de(de_0),
        .hs_r(hs),.vs_r(vs),.de_r(de),.vout_data(vout_data_raw)
    );
    assign vout_data = frame_ready && !underflow_flag ? vout_data_raw : 24'd0;
    wire [23:0] overlay_data;
    wire overlay_active;
    photo_badge_overlay #(.interaction_osd(1)) overlay_proc (
        .mem_clk(ext_mem_clk),.mem_rst_n(mem_rst_n),
        .clk(video_clk),.rst_n(pix_rst_n),.vs(vs),.de(de),.rgb_in(vout_data),
        .frame_sync(vs_0),.frame_commit(frame_commit),.active_index(active_index),
        .active_source_width(active_source_width),.active_source_height(active_source_height),
        .video_visible(frame_ready),.underflow_flag(underflow_flag),
        .menu_active(badge_menu_active),.menu_item(badge_menu_item),.music_volume(music_volume),
         .music_mute(music_mute),.auto_notice(auto_notice),.manual_notice(manual_notice),.manual_pause(badge_temporary_pause),
        .brightness_level(brightness_level),.slideshow_seconds(slideshow_seconds),.scene_mode(badge_scene_mode),
        .eye_mode(eye_mode),.transition_mode(transition_mode),
        .transition_alpha(transition_alpha),.transition_wipe_active(transition_wipe_active),
        .transition_wipe_ramp(transition_wipe_ramp),.exam_duration_index(exam_duration_index),
        .exam_started(exam_started),.exam_running(exam_timer_running),.exam_finished(exam_timer_finished),
        .exam_minutes(exam_remaining_minutes[7:0]),.exam_second(exam_remaining_second),
        .subtitle_enable(subtitle_enable),.subtitle_speed(subtitle_speed),.subtitle_alpha(subtitle_alpha),.subtitle_ready(subtitle_ready),
        .subtitle_notice_length(subtitle_notice_length),.subtitle_teacher_length(subtitle_teacher_length),
        .subtitle_mem_en(subtitle_mem_en),.subtitle_mem_write_en(subtitle_mem_write_en),.subtitle_mem_addr(subtitle_mem_addr),
        .subtitle_mem_write_data(subtitle_mem_write_data),.subtitle_mem_read_data(subtitle_mem_read_data),
        .rgb_out(overlay_data),.overlay_active(overlay_active),
        .frame_start_out(overlay_frame_start),.visible_index_out(overlay_visible_index),
         .visible_valid_out(overlay_visible_valid),.incoming_valid_out(overlay_incoming_valid),
         .incoming_index_out(overlay_incoming_index),.scene_visible_out(overlay_scene_visible),
         .visible_frame_pulse_out(overlay_visible_frame_pulse),
        .visible_source_width_out(visible_source_width),.visible_source_height_out(visible_source_height),
        .resolution_notice(resolution_notice),.tick_1ms(tick_1ms)
    );
    wire [7:0] image_number = active_index==9 ? 8'h10 : {4'd0,active_index+4'd1};
    wire [23:0] status_data = read_error != 0 ?
        {4'he,image_complete,read_error,8'd0} :
        audio_error ? {4'he,image_complete,8'h71,8'd0} :
        player_error != 0 ?
        {4'he,image_complete,player_error,8'd0} :
        config_error != 0 && display_ready && error_code == 0 ?
        {4'he,image_complete,config_error,8'd0} :
        subtitle_error != 0 && display_ready && error_code == 0 ?
        {4'he,image_complete,subtitle_error,8'd0} :
        display_ready && error_code == 0 ?
        {4'h3,image_complete,3'b000,auto_mode,image_number,save_status} :
        status_code==2 && error_code==0 ? {4'h2,image_complete,startup_detail} :
        {status_code,image_complete,error_code,error_detail};
    reg [23:0] status_meta, status_buf;
    always @(posedge clk or negedge system_rst_n) begin
        if (!system_rst_n) begin status_meta <= 0; status_buf <= 0; end
        else begin status_meta <= status_data; status_buf <= status_meta; end
    end
    wire [6:0] segment_data [0:5];
    genvar i;
    generate for (i=0;i<6;i=i+1) begin: segment_proc
        seg_decoder decoder_proc (.bin_data(status_buf[i*4 +: 4]),.seg_data(segment_data[i]));
    end endgenerate
    seg_scan seg_scan_m0 (
        .clk(clk),.rst_n(system_rst_n),.seg_sel(seg_sel),.seg_data(seg_data),
        .seg_data_0({1'b1,segment_data[5]}),.seg_data_1({1'b1,segment_data[4]}),
        .seg_data_2({1'b1,segment_data[3]}),.seg_data_3({1'b1,segment_data[2]}),
        .seg_data_4({1'b1,segment_data[1]}),.seg_data_5({1'b1,segment_data[0]})
    );
    wire audio_valid, acr_valid;
    wire [23:0] audio_left_data, audio_right_data;
    wire [19:0] acr_cts, acr_n;
    photo_audio_product audio_proc (
        .mem_clk(ext_mem_clk),.mem_rst_n(mem_rst_n),.clk(video_clk),.rst_n(pix_rst_n),
        .scene_mode(badge_scene_mode),.menu_active(badge_menu_active),.music_enable(music_enable),
        .source_enable(player_enable),.error_flag(audio_error),
        .music_volume(music_volume),.exam_running(exam_timer_running),.exam_finished(exam_timer_finished),
        .exam_reset(exam_reset),.remaining_seconds(exam_remaining_seconds),
         .visible_valid(overlay_visible_valid),.visible_index(overlay_visible_index),
         .scene_visible(overlay_scene_visible),.visible_frame_pulse(overlay_visible_frame_pulse),.reader_error(read_error),
        .hdmi_video_locked(hdmi_video_locked),
        .wav_ready(wav_ready),.wav_sample(wav_sample),.sample_tick(),.wav_consume(wav_consume),
        .frame_sync(vs_0),.video_de(de),.video_visible(frame_ready),.underflow_flag(underflow_flag),
        .audio_valid(audio_valid),.audio_left_data(audio_left_data),.audio_right_data(audio_right_data),
        .acr_valid(acr_valid),.acr_cts(acr_cts),.acr_n(acr_n),.music_ready(),.effect_active()
    );
    wire axis_s_user, axis_s_valid, axis_s_last, axis_s_ready;
    wire [23:0] axis_s_data;
    video_rgb_to_axis_640x480 u_video_rgb_to_axis_640x480 (
        .I_clk(video_clk),.I_rst(rst_all),.I_vs(vs),.I_de(de),.I_rgb(overlay_data),
        .O_video_user(axis_s_user),.O_video_valid(axis_s_valid),.O_video_last(axis_s_last),.O_video_data(axis_s_data)
    );
    wire edid_trig, edid_valid;
    wire [7:0] edid_data;
    startup_pulse #(.CNT_MAX(20'd100000)) u_startup_pulse (
        .I_clk(video_clk),.I_rst(rst_all),.O_pulse(edid_trig)
    );
    wire [9:0] tmds_ch0_data, tmds_ch1_data, tmds_ch2_data, tmds_clk_data;
    hdmi_1_4b_transmitter_core_wrapper #(
        .DEVICE("EG"),.HTOTAL(800),.HSA(96),.HFP(16),.HBP(48),.HACTIVE(640),
        .VTOTAL(525),.VSA(2),.VFP(10),.VBP(33),.VACTIVE(480),
        .VIDEO_VIC(1),.VIDEO_TPG("Disable"),.VIDEO_FORMAT("RGB"),
        .AUDIO_SAMPLE_RATE("48K"),.IIC_SCL_DIV(250)
    ) u_hdmi_1_4b_transmitter_core_wrapper (
        .I_pixel_clk(video_clk),.I_rst(rst_all),.I_edid_read_trig(edid_trig),
        .O_edid_read_valid(edid_valid),.O_edid_read_data(edid_data),
        .I_axis_s_user(axis_s_user),.I_axis_s_valid(axis_s_valid),.I_axis_s_last(axis_s_last),
        .I_axis_s_data(axis_s_data),.O_axis_s_ready(axis_s_ready),
        .I_audio_valid(audio_valid),.I_audio_left_data(audio_left_data),.I_audio_right_data(audio_right_data),
        .I_acr_valid(acr_valid),.I_acr_cts(acr_cts),.I_acr_n(acr_n),
        .O_video_locked(hdmi_video_locked),.O_ddc_scl(HDMI_DDC_SCL),.IO_ddc_sda(HDMI_DDC_SDA),
        .O_ch0_tmds_data(tmds_ch0_data),.O_ch1_tmds_data(tmds_ch1_data),
        .O_ch2_tmds_data(tmds_ch2_data),.O_clk_tmds_data(tmds_clk_data)
    );
    hdmi_phy_wrapper #(.DEVICE("EG")) u_hdmi2phy_wrapper (
        .I_pixel_clk(video_clk),.I_serial_clk(hdmi_5x_clk),.I_rst(rst_all),
        .I_tmds_channel_0(tmds_ch0_data),.I_tmds_channel_1(tmds_ch1_data),
        .I_tmds_channel_2(tmds_ch2_data),.I_tmds_channel_clk(tmds_clk_data),
        .O_tmds_ch0_p(HDMI_D0_P),.O_tmds_ch1_p(HDMI_D1_P),
        .O_tmds_ch2_p(HDMI_D2_P),.O_tmds_clk_p(HDMI_CLK_P)
    );
endmodule
