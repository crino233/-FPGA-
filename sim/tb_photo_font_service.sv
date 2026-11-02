`timescale 1ns/1ps
module tb_photo_font_service #(parameter integer missing_font=0);
    tb_photo_ten #(.group_prefetch_value(1),.subtitle_value(1),.startup_only(1),
        .font_cache_value(missing_font ? 3 : 2)) pipeline();
    integer result_file;
    initial begin
        result_file=$fopen(missing_font ? "tb_photo_font_missing.result" : "tb_photo_font_service.result","w");
        wait(pipeline.display_ready);
        if(!missing_font)begin
            wait(pipeline.dut.aux_active && pipeline.subtitle_index==2 && pipeline.sector_busy);
            @(negedge pipeline.clk);pipeline.group_selection=10'h0f0;
            pipeline.group_target_index=4;pipeline.group_target_valid=1;
            @(negedge pipeline.clk);pipeline.group_target_valid=0;
            wait(pipeline.subtitle_cancelled);
            wait(pipeline.subtitle_ready || pipeline.subtitle_error);
            if(pipeline.subtitle_error)$fatal(1,"font cancel/retry failed %h",pipeline.subtitle_error);
            wait(pipeline.checked_images[4]);
            $fdisplay(result_file,"PASS actual FAT font transaction cancelled by cold image, drained and retried with exact image pixels");
        end else begin
            wait(pipeline.subtitle_error);
            if(pipeline.subtitle_error!=8'h81 || pipeline.subtitle_ready)$fatal(1,"missing font error %h",pipeline.subtitle_error);
            wait(pipeline.checked_images[1]);
        end
        wait(pipeline.dut.cache_proc.state==7 && !pipeline.dut.fs_busy);
        if(pipeline.ingest_error || pipeline.reader_error || pipeline.max_refresh_gap>2500)$fatal(1,"font fault damaged picture/refresh");
        $fdisplay(result_file,"PASS %s",missing_font ? "tb_photo_font_missing" : "tb_photo_font_service");
        $fclose(result_file);$finish;
    end
endmodule
