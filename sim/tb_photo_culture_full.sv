`timescale 1ns/1ps
module tb_photo_culture_full;
    tb_photo_ten #(.full_size(1),.group_prefetch_value(1),.subtitle_value(1),
        .wav_value(1),.startup_only(1),.culture_priority_value(1)) pipeline();
    integer result_file,before_pcm,before_refresh,before_reads,before_subtitle;
    time manual_time,ready_time,visible_time;
    initial begin
        result_file=$fopen("tb_photo_culture_full.result","w");
        wait(pipeline.checked_images[1] && pipeline.subtitle_ready);
        @(negedge pipeline.clk);pipeline.group_selection=10'h0f0;
        pipeline.group_target_index=4;pipeline.group_target_valid=1;
        @(negedge pipeline.clk);pipeline.group_target_valid=0;
        wait(pipeline.checked_images[4] && !pipeline.request_busy);
        @(negedge pipeline.clk);pipeline.culture_auto=1;pipeline.culture_auto_step=1;
        @(negedge pipeline.clk);pipeline.culture_auto_step=0;
        wait(pipeline.checked_images[5] && !pipeline.request_busy);
        wait(pipeline.dut.fs_busy && pipeline.dut.file_index==6);
        @(negedge pipeline.clk);pipeline.culture_auto_step=1;
        @(negedge pipeline.clk);pipeline.culture_auto_step=0;
        wait(pipeline.requested_index==6 && pipeline.request_busy && !pipeline.target_ready);
        before_pcm=pipeline.wav_samples;before_refresh=pipeline.refresh_count;
        before_subtitle=pipeline.subtitle_checked_pixels;
        manual_time=$time;
        pipeline.event_proc(1);
        wait(pipeline.requested_index==4 && pipeline.target_ready);ready_time=$time;
        wait(pipeline.transition_visible_index==4 && !pipeline.request_busy);visible_time=$time;
        if(ready_time-manual_time>1000 || visible_time-manual_time>33600000)
            $fatal(1,"full culture resident previous latency ready=%0d visible=%0d",ready_time-manual_time,visible_time-manual_time);
        wait(pipeline.dut.cache_proc.state==7 && !pipeline.dut.fs_busy);
        if(pipeline.reader_error || pipeline.ingest_error || pipeline.subtitle_error || pipeline.wav_error || pipeline.max_refresh_gap>2500)
            $fatal(1,"culture priority damaged concurrent pipeline");
        if(pipeline.wav_samples<=before_pcm || pipeline.refresh_count<=before_refresh || pipeline.subtitle_checked_pixels<=before_subtitle)
            $fatal(1,"culture wait stopped PCM/subtitles/refresh");
        before_reads=pipeline.image_sectors[4]+pipeline.image_sectors[5]+pipeline.image_sectors[6]+pipeline.image_sectors[7];
        pipeline.next_image(5,0);pipeline.next_image(6,0);pipeline.next_image(7,0);pipeline.next_image(6,1);
        if(pipeline.image_sectors[4]+pipeline.image_sectors[5]+pipeline.image_sectors[6]+pipeline.image_sectors[7]!=before_reads)
            $fatal(1,"warm culture navigation reread image data");
        $fdisplay(result_file,"PASS slow PIC7 automatic wait on PIC6, resident manual previous ready=%0d ns visible=%0d ns, exact real SDRAM/video/subtitles and ordered PCM continue, warm PIC5..8 do not reread TF, refresh max=%0d cycles",ready_time-manual_time,visible_time-manual_time,pipeline.max_refresh_gap);
        $fdisplay(result_file,"PASS tb_photo_culture_full");$fclose(result_file);$finish;
    end
    initial begin #1500000000;$fatal(1,"full culture watchdog");end
endmodule
