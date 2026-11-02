`timescale 1ns/1ps
module photo_audio_monitor (
    input wire clk, input wire rst_n, input wire audio_enable,
    input wire sample_valid, input wire [23:0] left_data, input wire [23:0] right_data,
    input wire acr_valid, input wire [19:0] acr_n, input wire [19:0] acr_cts,
    output integer sample_count = 0, output integer acr_count = 0
);
    integer cycle_count = 0, last_sample = 0, last_acr = 0, last_acr_sample = 0;
    reg running_flag = 0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) running_flag <= 0;
        else running_flag <= 1;
    end
    always @(negedge clk) begin
        if (!rst_n) begin
            cycle_count = 0; last_sample = 0; last_acr = 0;
            last_acr_sample = 0; sample_count = 0; acr_count = 0;
        end else if (running_flag) begin
            cycle_count = cycle_count+1;
            if (sample_valid) begin
                sample_count = sample_count+1;
                if (last_sample != 0 && cycle_count-last_sample != 520 && cycle_count-last_sample != 521)
                    $fatal(1,"PCM sample gap=%0d cycles",cycle_count-last_sample);
                last_sample = cycle_count;
                if (left_data !== right_data || left_data[7:0] !== 0 ||
                    $isunknown(left_data) || $signed(left_data) > 3072000 || $signed(left_data) < -3072000)
                    $fatal(1,"PCM stereo/amplitude/alignment: %h/%h",left_data,right_data);
                if (!audio_enable && left_data !== 0) $fatal(1,"muted audio was not zero");
            end
            if (cycle_count%3125 == 0 && sample_count != cycle_count/3125*6)
                $fatal(1,"PCM rate: cycles=%0d samples=%0d",cycle_count,sample_count);
            if (acr_valid) begin
                acr_count = acr_count+1;
                if (acr_n !== 6144 || $isunknown(acr_cts) || acr_cts == 0)
                    $fatal(1,"invalid ACR N/CTS");
                if (last_acr != 0 && (cycle_count-last_acr != 25000 ||
                    sample_count-last_acr_sample != 48 || acr_cts != 25000))
                    $fatal(1,"steady ACR CTS=%0d cycles=%0d samples=%0d",
                        acr_cts,cycle_count-last_acr,sample_count-last_acr_sample);
                last_acr = cycle_count; last_acr_sample = sample_count;
            end
        end
    end
endmodule

module tb_photo_audio #(
    parameter integer image_count=4
);
    localparam integer index_bits=$clog2(image_count);
    integer result_file;
    initial result_file = $fopen(image_count==10 ? "tb_photo_audio_ten.result" : "tb_photo_audio.result","w");
    reg mem_clk = 0, pix_clk = 0, reset_req = 1;
    always #4 mem_clk = ~mem_clk;
    initial begin #3; forever #20 pix_clk = ~pix_clk; end
    wire mem_rst_n, pix_rst_n;
    photo_reset_sync mem_reset_proc (.clk(mem_clk),.reset_req(reset_req),.rst_n(mem_rst_n));
    photo_reset_sync pix_reset_proc (.clk(pix_clk),.reset_req(reset_req),.rst_n(pix_rst_n));
    reg source_enable = 0, frame_commit = 0, video_vsync = 1, music_enable = 1;
    reg video_de = 0, video_visible = 0, underflow_flag = 0;
    reg [index_bits-1:0] active_index = 0;
    wire audio_valid, acr_valid, error_flag;
    wire [23:0] left_data, right_data;
    wire [19:0] acr_n, acr_cts;
    wire [31:0] sample_count, acr_count;
    photo_audio #(.note_samples(8),.cue_samples(4),.image_count(image_count)) audio_proc (
        .mem_clk(mem_clk),.mem_rst_n(mem_rst_n),.pix_clk(pix_clk),.pix_rst_n(pix_rst_n),
        .source_enable(source_enable),.frame_commit(frame_commit),.music_enable(music_enable),.active_index(active_index),
        .audio_scene(2'd0),.music_volume(3'd4),
        .frame_sync(video_vsync),.video_de(video_de),.video_visible(video_visible),
        .underflow_flag(underflow_flag),.audio_valid(audio_valid),
        .audio_left_data(left_data),.audio_right_data(right_data),
        .acr_valid(acr_valid),.acr_n(acr_n),.acr_cts(acr_cts),.error_flag(error_flag)
    );
    photo_audio_monitor monitor_proc (
        .clk(pix_clk),.rst_n(pix_rst_n),.audio_enable(audio_proc.audio_enable),
        .sample_valid(audio_valid),.left_data(left_data),.right_data(right_data),
        .acr_valid(acr_valid),.acr_n(acr_n),.acr_cts(acr_cts),
        .sample_count(sample_count),.acr_count(acr_count)
    );
    reg fixed_enable = 0;
    wire fixed_valid;
    wire signed [15:0] fixed_data;
    photo_audio_tone #(.test_mode(1),.image_count(image_count)) fixed_proc (
        .clk(pix_clk),.rst_n(pix_rst_n),.enable(fixed_enable),.music_enable(1'b1),.image_change(1'b0),
        .image_index({index_bits{1'b0}}),.audio_scene(2'd0),.music_volume(3'd4),
        .sample_valid(fixed_valid),.sample_data(fixed_data),.cue_active()
    );
    integer fixed_phase = 0, fixed_count = 0, expected_sample;
    real sine_val;
    always @(negedge pix_clk) begin
        if (!pix_rst_n) begin fixed_phase = 0; fixed_count = 0; end
        else if (fixed_valid) begin
            if (fixed_enable) begin
                sine_val = 12000.0*$sin(6.283185307179586*(fixed_phase >> 14)/64.0);
                expected_sample = $rtoi(sine_val+(sine_val < 0 ? -0.5 : 0.5));
                if (fixed_data != expected_sample)
                    $fatal(1,"sine mismatch phase=%0d got=%0d expected=%0d",fixed_phase,fixed_data,expected_sample);
                fixed_phase = (fixed_phase+21845) & 1048575; fixed_count = fixed_count+1;
            end else begin
                if (fixed_data !== 0) $fatal(1,"fixed tone mute");
                fixed_phase = 0;
            end
        end
    end
    integer change_count = 0;
    reg [image_count*6-1:0] note_coverage = 0;
    always @(negedge pix_clk) begin
        if (!pix_rst_n) begin change_count = 0; note_coverage = 0; end
        else begin
            if (audio_proc.image_change) change_count = change_count+1;
            if (audio_valid && audio_proc.audio_enable && !audio_proc.tone_proc.cue_active)
                note_coverage[audio_proc.image_index*6+audio_proc.tone_proc.note_index] = 1;
        end
    end
    task automatic commit_proc(input integer index);
        begin
            @(negedge mem_clk); active_index = index; frame_commit = 1;
            @(negedge mem_clk); frame_commit = 0;
        end
    endtask
    task automatic frame_proc(input integer index);
        reg [index_bits-1:0] old_index;
        reg was_linked;
        integer before_changes;
        begin
            old_index = audio_proc.image_index; was_linked = audio_proc.linked_flag; before_changes = change_count;
            @(negedge pix_clk); video_vsync = 0;
            commit_proc(index);
            repeat(30) @(negedge pix_clk);
            if (audio_proc.image_index != old_index || audio_proc.linked_flag != was_linked)
                $fatal(1,"image changed before DE");
            video_vsync = 1; video_visible = 1;
            repeat(10) @(negedge pix_clk);
            video_de = 1;
            repeat(5) @(negedge pix_clk);
            if (error_flag || audio_proc.image_index != index || !audio_proc.audio_enable)
                $fatal(1,"frame/audio commit index=%0d got=%0d error=%b",index,audio_proc.image_index,error_flag);
            if(change_count!=before_changes+(!was_linked || old_index!=index))
                $fatal(1,"cue did not track full logical index=%0d",index);
            video_de = 0;
        end
    endtask
    integer old_changes, sample_target, audible_samples;
    reg [19:0] old_phase;
    initial begin
        #157; reset_req = 0;
        wait(pix_rst_n); repeat(10000) @(negedge pix_clk);
        if (left_data !== 0 || audio_proc.audio_enable) $fatal(1,"startup not silent");
        fixed_enable = 1; source_enable = 1;
        frame_proc(0);
        for (integer image = 0; image < image_count; image = image+1) begin
            if (image != 0) frame_proc(image);
            sample_target = sample_count+60;
            wait(sample_count >= sample_target);
            repeat(2) @(negedge pix_clk);
        end
        if (note_coverage !== {image_count*6{1'b1}}) $fatal(1,"melody coverage=%h",note_coverage);
        old_changes = change_count;
        frame_proc(image_count-1);
        if (change_count != old_changes) $fatal(1,"same-image frame restarted cue");
        frame_proc(0); frame_proc(image_count-1);
        if(image_count==10) begin frame_proc(4);frame_proc(8);frame_proc(0); end
        wait(fixed_count >= 300);
        if (acr_count < 5) $fatal(1,"ACR coverage incomplete");
        $fdisplay(result_file,"PASS 48 kHz rational cadence, 64-point sine vs mathematical reference, signed PCM16-to-24 stereo, steady N=6144 CTS=25000");
        $fdisplay(result_file,"PASS complete-index handshake, first-DE commit, %0d melody slots, cue expiry, same-image no retrigger, logical-ID wraps",image_count*6);
        @(negedge pix_clk);video_visible=0;
        sample_target=sample_count+5;wait(sample_count>=sample_target);
        if(!audio_proc.audio_enable) $fatal(1,"normal frame prefetch restarted the audio source");
        @(negedge pix_clk);video_visible=1;
        $fdisplay(result_file,"PASS audio continues across normal frame-prefetch readiness gaps");
        old_changes=change_count; old_phase=audio_proc.tone_proc.phase;
        @(negedge mem_clk); music_enable=0;
        sample_target=sample_count+12; wait(sample_count>=sample_target);
        repeat(2) @(negedge pix_clk);
        if(left_data!==0 || !audio_proc.audio_enable || change_count!=old_changes ||
           audio_proc.tone_proc.phase==old_phase)
            $fatal(1,"music mute stopped/restarted the source or leaked melody");
        frame_proc(active_index==0 ? 1 : 0);
        audible_samples=0;
        repeat(5) begin
            sample_target=sample_count+1; wait(sample_count>=sample_target);
            @(negedge pix_clk);
            if(left_data!=0) audible_samples=audible_samples+1;
        end
        if(audible_samples==0) $fatal(1,"SW1 mute suppressed change cue");
        @(negedge mem_clk); music_enable=1;
        old_changes=change_count; audible_samples=0;
        repeat(12) begin
            sample_target=sample_count+1; wait(sample_count>=sample_target);
            @(negedge pix_clk);
            if(left_data!=0) audible_samples=audible_samples+1;
        end
        if(audible_samples==0 || change_count!=old_changes || error_flag)
            $fatal(1,"music unmute failed or retriggered the image cue");
        $fdisplay(result_file,"PASS synchronized music mute/unmute preserves DDS, cue and PCM/ACR cadence");
        @(negedge pix_clk); underflow_flag = 1;
        sample_target = sample_count+60; wait(sample_count >= sample_target);
        if (left_data !== 0 || audio_proc.audio_enable) $fatal(1,"underflow did not mute");
        @(negedge pix_clk); underflow_flag = 0;
        sample_target = sample_count+5; wait(sample_count >= sample_target);
        @(negedge mem_clk); source_enable = 0;
        sample_target = sample_count+60; wait(sample_count >= sample_target);
        if (left_data !== 0) $fatal(1,"disabled stream not silent");
        $fdisplay(result_file,"PASS silence during startup, underflow and disable; sample/ACR cadence uninterrupted");
        @(negedge mem_clk); source_enable = 1;
        repeat(10) @(negedge pix_clk);
        commit_proc(2);
        wait(error_flag);
        sample_target = sample_count+5; wait(sample_count >= sample_target);
        if (left_data !== 0) $fatal(1,"late update fault not silent");
        $fdisplay(result_file,"PASS late mid-frame index rejected and muted");
        #13; reset_req = 1;
        #1; if (mem_rst_n !== 0 || pix_rst_n !== 0) $fatal(1,"reset not asynchronous");
        frame_commit = 0; video_de = 0; video_visible = 0; video_vsync = 1; fixed_enable = 0;
        #197; reset_req = 0;
        wait(pix_rst_n); repeat(20) @(negedge pix_clk);
        frame_proc(1);
        sample_target = sample_count+100; wait(sample_count >= sample_target);
        if (error_flag || acr_count < 2) $fatal(1,"reset recovery failed");
        $fdisplay(result_file,"PASS domain reset and fresh handshake/audio/ACR recovery");
        @(negedge pix_clk); video_vsync = 0;
        commit_proc(0);
        commit_proc(3);
        wait(error_flag);
        sample_target = sample_count+5; wait(sample_count >= sample_target);
        if (!audio_proc.source_error || audio_proc.held_index != 0 || left_data !== 0)
            $fatal(1,"busy mailbox update was not rejected");
        $fdisplay(result_file,"PASS busy-mailbox overwrite rejected, held payload preserved and audio muted");
        $fdisplay(result_file,"INFO application/official ACR RTL only; no physical HDMI/PLL/audio validation");
        $fdisplay(result_file,"%s",image_count==10 ? "PASS tb_photo_audio_ten" : "PASS tb_photo_audio"); $fclose(result_file); $finish;
    end
    initial begin #40000000; $fatal(1,"audio watchdog"); end
endmodule
