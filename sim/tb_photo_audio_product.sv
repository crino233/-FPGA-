`timescale 1ns/1ps
module tb_photo_audio_product;
    reg mem_clk=0,clk=0,mem_rst_n=0,rst_n=0;
    always #4 mem_clk=~mem_clk;
    always #20 clk=~clk;
    reg [1:0] scene=0;
    reg menu=0,music_enable=1,running=0,finished=0,reset_cmd=0;
    reg [2:0] volume=4;
    reg [31:0] seconds=1800;
    reg vs=1,de=0,visible=0,underflow=0,visible_valid=0;
    reg scene_visible=0,visible_frame_pulse=0,hdmi_video_locked=0;
    reg [7:0] reader_error=0;
    reg [3:0] index=1;
    wire valid,consume,ready,effect;
    wire [23:0] pcm,pcm_right;
    wire acr_valid;wire [19:0] cts,n;
    integer result_file,samples=0,last_sample=0,cycles=0,fire_nonzero=0;
    photo_audio_product #(.frame_pixels(16),.unit_samples(8)) dut(
        .mem_clk(mem_clk),.mem_rst_n(mem_rst_n),.clk(clk),.rst_n(rst_n),
        .scene_mode(scene),.menu_active(menu),.music_enable(music_enable),.music_volume(volume),
        .source_enable(1'b1),.error_flag(),
        .exam_running(running),.exam_finished(finished),.exam_reset(reset_cmd),.remaining_seconds(seconds),
        .frame_sync(vs),.video_de(de),.video_visible(visible),.underflow_flag(underflow),
        .scene_visible(scene_visible),.visible_frame_pulse(visible_frame_pulse),.reader_error(reader_error),
        .hdmi_video_locked(hdmi_video_locked),
        .visible_valid(visible_valid),.visible_index(index),.wav_ready(1'b1),.wav_sample(16'sd1234),
        .sample_tick(),.wav_consume(consume),.audio_valid(valid),.audio_left_data(pcm),.audio_right_data(pcm_right),
        .acr_valid(acr_valid),.acr_cts(cts),.acr_n(n),.music_ready(ready),.effect_active(effect));
    always @(posedge clk)begin
        cycles<=cycles+1;
        if(rst_n && valid)begin
            if(samples>0 && cycles-last_sample!=520 && cycles-last_sample!=521)$fatal(1,"sample cadence");
            if(pcm!==pcm_right)$fatal(1,"stereo alignment");
            last_sample<=cycles;samples<=samples+1;
        end
    end
    task boundary;begin @(negedge clk);vs=0;repeat(3)@(negedge clk);vs=1;end endtask
    task frame(input bit good);begin
        boundary();visible=good;visible_valid=1;de=1;repeat(16)@(negedge clk);de=0;repeat(3)@(negedge clk);
    end endtask
    task wait_effect(input integer code);begin
        wait(dut.effect==code);repeat(100)@(negedge clk);
    end endtask
    initial begin
        result_file=$fopen("tb_photo_audio_product.result","w");
        repeat(8)@(negedge clk);mem_rst_n=1;rst_n=1;
        repeat(20)@(negedge clk);
        if(dut.startup_started || ready || consume)$fatal(1,"startup audio admitted before visible picture");
        frame(0);boundary();if(ready)$fatal(1,"invalid raster admitted music");
        frame(1);
        repeat(5000)begin
            @(negedge clk);
            if(valid && pcm!=0)$fatal(1,"startup cue spent before first complete output frame");
        end
        @(negedge clk);visible_frame_pulse=1;@(negedge clk);visible_frame_pulse=0;
        wait(dut.startup_done);
        repeat(4)@(negedge clk);
        if(!ready)$fatal(1,"complete visible raster rejected");
        if(dut.startup_started===1'b0)$fatal(1,"startup cue was not armed by visible output");
        hdmi_video_locked=1;
        wait(valid);@(negedge clk);if(pcm!==24'h04d200)$fatal(1,"music PCM %h",pcm);
        underflow=1;repeat(5)@(negedge clk);if(!ready)$fatal(1,"ordinary image load interrupted music qualification");underflow=0;
        music_enable=0;repeat(30)@(negedge clk);wait(valid);@(negedge clk);
        if(pcm!=0 || !dut.startup_done)$fatal(1,"mute/state");
        scene=1;seconds=60;repeat(30)@(negedge clk);running=1;wait_effect(1);
        wait(dut.effect==0);running=0;wait_effect(2);wait(dut.effect==0);
        running=1;wait_effect(3);wait(dut.effect==0);
        seconds=11;repeat(10)@(negedge mem_clk);seconds=10;wait_effect(5);wait(dut.effect==0);
        seconds=61;repeat(10)@(negedge mem_clk);seconds=60;wait_effect(4);
        scene=2;index=9;visible_valid=1;visible=1;de=1;scene_visible=0;repeat(30)@(negedge clk);
        if(valid && pcm!=0)$fatal(1,"fire started before scene became visible");
        scene_visible=1;
        repeat(8)begin wait(valid);if(pcm!=0)fire_nonzero=1;@(negedge clk);end
        if(!fire_nonzero)$fatal(1,"muted fire");
        scene=1;running=0;repeat(30)@(negedge clk);if(effect)$fatal(1,"stale cue replay");
        running=1;repeat(30)@(negedge clk);wait(dut.effect==0);
        running=0;finished=1;seconds=0;wait_effect(6);wait(dut.effect==0);
        reset_cmd=1;repeat(8)@(negedge mem_clk);reset_cmd=0;finished=0;seconds=60;
        scene=0;index=8;repeat(30)@(negedge clk);if(consume)$fatal(1,"PIC9 return admitted ordinary music");
        $fdisplay(result_file,"PASS boot cue expiry stays silent until a complete valid raster; continuous 48k PCM/ACR and signed stereo");
        $fdisplay(result_file,"PASS start/pause/resume/60s/10s/end once, fire preempts mute and cancels old cues, PIC9 return gate");
        $fdisplay(result_file,"PASS tb_photo_audio_product");$fclose(result_file);$finish;
    end
    initial begin #100000000;$fatal(1,"product audio watchdog effect=%0d scene=%0d",dut.effect,dut.scene);end
endmodule
