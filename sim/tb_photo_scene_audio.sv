`timescale 1ns/1ps
module tb_photo_scene_audio;
    reg mem_clk=0, pix_clk=0, reset_req=1;
    always #4 mem_clk=~mem_clk;
    initial begin #3; forever #20 pix_clk=~pix_clk; end
    wire mem_rst_n,pix_rst_n;
    photo_reset_sync mem_reset_proc(.clk(mem_clk),.reset_req(reset_req),.rst_n(mem_rst_n));
    photo_reset_sync pix_reset_proc(.clk(pix_clk),.reset_req(reset_req),.rst_n(pix_rst_n));
    reg source_enable=0,frame_commit=0,music_enable=1;
    reg [2:0] music_volume=4;
    reg [1:0] audio_scene=0;
    reg [3:0] active_index=0;
    reg frame_sync=1,video_de=0,video_visible=0,underflow_flag=0;
    wire audio_valid,acr_valid,error_flag;
    wire [23:0] left_data,right_data;
    wire [19:0] acr_n,acr_cts;
    wire [31:0] sample_count,acr_count;
    integer result_file,change_count=0,compared_samples=0;
    integer index,level,value,expected,actual,target;
    integer positive_seen=0,negative_seen=0,cue_seen=0;
    reg sampled_cue,sampled_music;
    reg [2:0] sampled_volume;
    photo_audio #(.note_samples(8),.cue_samples(4),.image_count(10),.scene_audio(1)) dut(
        .mem_clk(mem_clk),.mem_rst_n(mem_rst_n),.pix_clk(pix_clk),.pix_rst_n(pix_rst_n),
        .source_enable(source_enable),.frame_commit(frame_commit),.music_enable(music_enable),
        .audio_scene(audio_scene),.music_volume(music_volume),.active_index(active_index),
        .frame_sync(frame_sync),.video_de(video_de),.video_visible(video_visible),.underflow_flag(underflow_flag),
        .audio_valid(audio_valid),.audio_left_data(left_data),.audio_right_data(right_data),
        .acr_valid(acr_valid),.acr_n(acr_n),.acr_cts(acr_cts),.error_flag(error_flag)
    );
    photo_audio_monitor monitor_proc(
        .clk(pix_clk),.rst_n(pix_rst_n),.audio_enable(dut.audio_enable),.sample_valid(audio_valid),
        .left_data(left_data),.right_data(right_data),.acr_valid(acr_valid),.acr_n(acr_n),.acr_cts(acr_cts),
        .sample_count(sample_count),.acr_count(acr_count)
    );
    wire reference_valid;
    wire signed [15:0] reference_data;
    photo_audio_tone #(.note_samples(8),.cue_samples(4),.image_count(10),.shared_music(1)) reference_proc(
        .clk(pix_clk),.rst_n(pix_rst_n),.enable(dut.audio_enable),.music_enable(1'b1),
        .image_change(dut.image_change),.image_index(4'd0),.audio_scene(2'd0),.music_volume(3'd4),
        .sample_valid(reference_valid),.sample_data(reference_data),.cue_active()
    );
    always @(posedge pix_clk) if(pix_rst_n && dut.tone_proc.sample_tick) begin
        sampled_cue=dut.tone_proc.cue_count!=0;
        sampled_music=dut.music_enable_pix;
        sampled_volume=dut.music_volume_pix;
    end
    always @(negedge pix_clk) if(pix_rst_n) begin
        if(dut.image_change)change_count=change_count+1;
        if(audio_valid && dut.audio_enable)begin
            if(!reference_valid)$fatal(1,"sample cadence diverged from reference");
            expected=$signed(reference_data);
            if(sampled_cue)cue_seen=cue_seen+1;
            else if(!sampled_music)expected=0;
            else expected=(expected*$signed({1'b0,sampled_volume}))>>>2;
            actual=$signed(left_data)>>>8;
            if(actual!==expected)$fatal(1,"scaled PCM got=%0d expected=%0d cue=%b level=%0d",actual,expected,sampled_cue,sampled_volume);
            if(reference_data>0)positive_seen=positive_seen+1;
            if(reference_data<0)negative_seen=negative_seen+1;
            if(dut.tone_proc.phase!==reference_proc.phase || dut.tone_proc.note_index!==reference_proc.note_index)
                $fatal(1,"picture/mode/volume change restarted shared melody");
            compared_samples=compared_samples+1;
        end
    end
    task samples_proc(input integer count);
        integer stop_count;
        begin stop_count=sample_count+count;wait(sample_count>=stop_count);@(negedge pix_clk);end
    endtask
    task config_proc(input bit enabled,input [2:0] volume);
        begin
            @(negedge mem_clk);music_enable=enabled;music_volume=volume;
            repeat(40)@(negedge pix_clk);
            if(dut.music_enable_pix!==enabled || dut.music_volume_pix!==volume)
                $fatal(1,"coherent audio configuration did not settle");
        end
    endtask
    task frame_proc(input [3:0] image,input bit delayed_visible);
        reg [3:0] old_image;
        reg [1:0] expected_scene;
        begin
            old_image=dut.image_index;
            expected_scene=image==9 ? 2 : image==8 ? 1 : 0;
            @(negedge pix_clk);frame_sync=0;video_de=0;
            @(negedge mem_clk);active_index=image;audio_scene=expected_scene;frame_commit=1;
            @(negedge mem_clk);frame_commit=0;
            repeat(30)@(negedge pix_clk);
            if(dut.image_index!==old_image)$fatal(1,"logical image updated before valid pixels");
            frame_sync=1;video_visible=!delayed_visible;video_de=1;
            if(delayed_visible)begin
                repeat(5)@(negedge pix_clk);
                if(!dut.frame_wait || dut.linked_flag)$fatal(1,"invalid DE consumed first-frame mailbox");
                video_visible=1;
            end
            repeat(5)@(negedge pix_clk);
            if(error_flag || !dut.audio_enable || dut.image_index!==image || dut.active_scene!==expected_scene)
                $fatal(1,"scene/image commit mismatch image=%0d scene=%0d",image,dut.active_scene);
            video_de=0;
        end
    endtask
    initial begin
        result_file=$fopen("tb_photo_scene_audio.result","w");
        for(level=0;level<5;level=level+1)for(value=-32768;value<=32767;value=value+1)begin
            expected=(value*level)>>>2;
            actual=$signed(dut.tone_proc.volume_proc(16'(value),3'(level)));
            if(actual!==expected)$fatal(1,"signed volume function value=%0d level=%0d got=%0d expected=%0d",value,level,actual,expected);
        end
        $fdisplay(result_file,"PASS exhaustive 65536 signed PCM values at all five gains, no overflow and exact unity");
        #157;reset_req=0;wait(pix_rst_n);repeat(20)@(negedge pix_clk);
        config_proc(0,0);source_enable=1;
        repeat(10)@(negedge pix_clk);frame_proc(1,1);
        samples_proc(12);
        if(change_count!=1 || cue_seen==0 || left_data!==0)$fatal(1,"single cue/zero-gain mute separation");
        config_proc(1,4);samples_proc(70);
        for(index=0;index<10;index=index+1)begin
            frame_proc(index,0);samples_proc(12);
            if(change_count!=1)$fatal(1,"ordinary/scene navigation retriggered startup cue");
        end
        for(level=0;level<5;level=level+1)begin
            config_proc(1,3'(level));samples_proc(64);
        end
        config_proc(0,4);samples_proc(12);
        if(left_data!==0)$fatal(1,"SW1 mute leaked melody");
        config_proc(1,4);samples_proc(12);
        @(negedge mem_clk);music_volume=1;
        @(negedge mem_clk);music_volume=3;music_enable=0;
        @(negedge mem_clk);music_volume=2;music_enable=1;
        repeat(40)@(negedge pix_clk);
        if(!dut.music_enable_pix || dut.music_volume_pix!=2)$fatal(1,"latest busy configuration lost");
        samples_proc(20);
        $fdisplay(result_file,"PASS ten logical images/three scene entries share one existing melody without cue or phase restart");
        $fdisplay(result_file,"PASS coherent mute/volume mailbox, latest busy update, five gains and independent startup cue");
        @(negedge pix_clk);video_visible=0;samples_proc(8);
        if(!dut.audio_enable)$fatal(1,"normal prefetch gap stopped music");
        video_visible=1;underflow_flag=1;samples_proc(5);
        if(left_data!==0)$fatal(1,"underflow output not silent");
        underflow_flag=0;samples_proc(5);source_enable=0;samples_proc(5);
        if(left_data!==0)$fatal(1,"source disable output not silent");
        if(error_flag || compared_samples<500 || positive_seen==0 || negative_seen==0 || acr_count<5)
            $fatal(1,"insufficient PCM/ACR/sign coverage");
        $fdisplay(result_file,"PASS continuous PCM/ACR during navigation, mute, zero gain, prefetch, underflow and disable");
        $fdisplay(result_file,"INFO startup cue/wait/music hardware timing BUG remains open; no reader changes or hardware validation");
        $fdisplay(result_file,"PASS tb_photo_scene_audio");$fclose(result_file);$finish;
    end
    initial begin #50000000;$fatal(1,"scene audio watchdog");end
endmodule
