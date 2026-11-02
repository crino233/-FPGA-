`timescale 1ns/1ps
module tb_photo_startup_subtitle #(
    parameter integer require_early=1,
    parameter integer sector_delay_cycles=0,
    parameter integer font_cache_value=0
);
    tb_photo_ten #(.full_size(1),.group_prefetch_value(1),.subtitle_value(1),
        .wav_value(1),.image_scale_value(1),.startup_only(1),
        .sector_delay_cycles(sector_delay_cycles),.font_cache_value(font_cache_value)) pipeline();

    integer trace_file;
    time display_time=0,clean_start_time=0,clean_end_time=0,frame_pulse_time=0;
    time wav_ready_time=0,wav_consume_time=0,subtitle_ready_time=0;
    time subtitle_loaded_time=0,subtitle_visible_time=0,subtitle_strip_time=0,subtitle_ink_time=0;
    time background_start_time=0;
    integer frame_pixels=0,clean_frames=0,subtitle_cancels=0;
    integer first_glyph=-1;
    reg [15:0] first_code;
    reg frame_bad=0,vs_old=1;
    reg urgent_old=0,aux_old=0;
    reg [1:0] owner_old=0;

    task event_proc(input string event_name);
        $fdisplay(trace_file,"%0d,%s,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%h",
            $time,event_name,pipeline.dut.wav_service_proc.sector_proc.owner,
            pipeline.dut.card_sector_lba,pipeline.dut.fs_proc.state,
            pipeline.dut.wav_service_proc.audio_fs_proc.state,pipeline.dut.audio_urgent,
            pipeline.dut.aux_active,pipeline.dut.wav_service_proc.stream_proc.used_write,pipeline.complete);
    endtask

    initial begin
        trace_file=$fopen("tb_photo_startup_subtitle_trace.csv","w");
        if(trace_file==0)$fatal(1,"cannot open startup trace");
        $fdisplay(trace_file,"time_ns,event,owner,lba,image_fs_state,audio_fs_state,audio_urgent,aux_active,pcm_buffer_samples,cache_mask");
        #1;
        first_code={pipeline.subtitle_notice[0][3:0],pipeline.subtitle_notice[1][5:0],pipeline.subtitle_notice[2][5:0]};
        for(integer i=0;i<80;i=i+1)
            if(pipeline.subtitle_expected_rows[1280+i]==first_code)first_glyph=i;
        if(first_glyph<0 && !font_cache_value)$fatal(1,"first subtitle character has no independent font oracle");
        wait(display_time!=0 && clean_end_time!=0 && wav_consume_time!=0 && subtitle_ink_time!=0);
        wait(pipeline.wav_samples>=4096 && pipeline.dut.cache_proc.state==7 && !pipeline.dut.fs_busy);
        repeat(8)@(negedge pipeline.pix_clk);
        if(pipeline.wav_error || pipeline.subtitle_error || pipeline.reader_error || pipeline.ingest_error)
            $fatal(1,"startup ended with a product error");
        if(pipeline.dut.wav_service_proc.stream_proc.underflows!=0)
            $fatal(1,"startup WAV underflow");
        if(require_early && (background_start_time==0 || subtitle_ready_time>background_start_time || subtitle_cancels!=0))
            $fatal(1,"background prefetch delayed or cancelled startup subtitles");
        if(require_early && subtitle_ink_time>wav_consume_time)
            $fatal(1,"first subtitle glyph appeared after ordinary WAV admission");
        $fdisplay(pipeline.result_file,"TIME display_ready_ns=%0d",display_time);
        $fdisplay(pipeline.result_file,"TIME first_clean_frame_start_ns=%0d",clean_start_time);
        $fdisplay(pipeline.result_file,"TIME first_clean_frame_end_ns=%0d",clean_end_time);
        $fdisplay(pipeline.result_file,"TIME visible_frame_pulse_ns=%0d",frame_pulse_time);
        $fdisplay(pipeline.result_file,"TIME wav_ready_ns=%0d",wav_ready_time);
        $fdisplay(pipeline.result_file,"TIME first_wav_consume_ns=%0d",wav_consume_time);
        $fdisplay(pipeline.result_file,"TIME subtitle_ready_ns=%0d",subtitle_ready_time);
        $fdisplay(pipeline.result_file,"TIME subtitle_loaded_ns=%0d",subtitle_loaded_time);
        $fdisplay(pipeline.result_file,"TIME subtitle_visible_ns=%0d",subtitle_visible_time);
        $fdisplay(pipeline.result_file,"TIME first_subtitle_strip_ns=%0d",subtitle_strip_time);
        $fdisplay(pipeline.result_file,"TIME first_subtitle_ink_ns=%0d",subtitle_ink_time);
        $fdisplay(pipeline.result_file,"TIME background_file_start_ns=%0d",background_start_time);
        $fdisplay(pipeline.result_file,"INFO subtitle_cancels=%0d clean_frames=%0d ordered_pcm=%0d refresh_max=%0d",
            subtitle_cancels,clean_frames,pipeline.wav_samples,pipeline.max_refresh_gap);
        $fdisplay(pipeline.result_file,"PASS tb_photo_startup_subtitle");
        $fclose(pipeline.result_file);$fclose(trace_file);$finish;
    end

    always @(posedge pipeline.clk)begin
        #1;
        if(pipeline.rst_n)begin
            if(pipeline.display_ready && display_time==0)begin display_time=$time;event_proc("display_ready");end
            if(pipeline.dut.card_sector_req)event_proc("sector_start");
            if(pipeline.dut.card_sector_done)event_proc("sector_done");
            if(pipeline.dut.image_request_reg)event_proc("image_file_request");
            if(pipeline.dut.aux_request_reg)event_proc("subtitle_file_request");
            if(pipeline.subtitle_start)event_proc("subtitle_file_start");
            if(pipeline.subtitle_end)begin
                event_proc(pipeline.subtitle_cancelled ? "subtitle_cancel" : "subtitle_file_end");
                if(pipeline.subtitle_cancelled)subtitle_cancels=subtitle_cancels+1;
            end
            if(pipeline.subtitle_finished)event_proc("subtitle_file_finished");
            if(pipeline.subtitle_ready && subtitle_ready_time==0)begin subtitle_ready_time=$time;event_proc("subtitle_ready");end
            if(pipeline.dut.file_start && !pipeline.dut.aux_active && pipeline.display_ready && background_start_time==0)begin
                background_start_time=$time;event_proc("background_file_start");
            end
            if(owner_old!=pipeline.dut.wav_service_proc.sector_proc.owner || urgent_old!=pipeline.dut.audio_urgent || aux_old!=pipeline.dut.aux_active)
                event_proc("service_state");
            owner_old=pipeline.dut.wav_service_proc.sector_proc.owner;
            urgent_old=pipeline.dut.audio_urgent;aux_old=pipeline.dut.aux_active;
        end
    end

    always @(posedge pipeline.pix_clk)if(pipeline.rst_n)begin
        if(pipeline.wav_ready && wav_ready_time==0)begin wav_ready_time=$time;event_proc("wav_ready");end
        if(pipeline.wav_consume && pipeline.wav_ready && wav_consume_time==0)begin
            wav_consume_time=$time;event_proc("first_wav_consume");
        end
    end

    always @(negedge pipeline.pix_clk)begin
        #1;
        if(pipeline.rst_n)begin
            if(vs_old && !pipeline.final_vs)begin
                frame_pixels=0;frame_bad=0;event_proc("frame_start");
            end
            vs_old=pipeline.final_vs;
            if(pipeline.transition_visible_frame_pulse && frame_pulse_time==0)begin
                frame_pulse_time=$time;event_proc("visible_frame_pulse");
            end
            if(pipeline.overlay_proc.overlay.subtitle_loaded && subtitle_loaded_time==0)begin
                subtitle_loaded_time=$time;event_proc("subtitle_loaded");
            end
            if(pipeline.overlay_proc.overlay.subtitle_visible && subtitle_visible_time==0)begin
                subtitle_visible_time=$time;event_proc("subtitle_visible");
            end
            if(pipeline.video_de)begin
                if(!pipeline.frame_ready || pipeline.underflow)frame_bad=1;
                else begin
                    if(frame_pixels==0 && clean_start_time==0)clean_start_time=$time;
                    if(pipeline.video_pixel!==pipeline.expected_pixel(1,frame_pixels))
                        $fatal(1,"startup image pixel mismatch at %0d",frame_pixels);
                    frame_pixels=frame_pixels+1;
                    if(frame_pixels==307200 && !frame_bad)begin
                        clean_frames=clean_frames+1;
                        if(clean_end_time==0)begin clean_end_time=$time;event_proc("first_clean_frame_end");end
                    end
                end
                if(pipeline.overlay_proc.overlay.subtitle_visible &&
                    pipeline.overlay_proc.overlay.pixel_x>=16 && pipeline.overlay_proc.overlay.pixel_x<624 &&
                    pipeline.overlay_proc.overlay.pixel_y>=440 && pipeline.overlay_proc.overlay.pixel_y<472)begin
                    integer dx,y;
                    if(subtitle_strip_time==0)begin subtitle_strip_time=$time;event_proc("first_subtitle_strip");end
                    dx=pipeline.overlay_proc.overlay.pixel_x+pipeline.overlay_proc.overlay.subtitle_scroll-624;
                    y=pipeline.overlay_proc.overlay.pixel_y;
                    if(font_cache_value)first_glyph=pipeline.subtitle_character_map[0];
                    if(dx>=0 && dx<16 && y>=448 && y<464 &&
                        pipeline.subtitle_expected_rows[first_glyph*16+y-448][15-dx] &&
                        pipeline.transition_pixel===24'heef3f5 && subtitle_ink_time==0)begin
                        subtitle_ink_time=$time;event_proc("first_subtitle_ink");
                    end
                end
            end
        end
    end
endmodule
