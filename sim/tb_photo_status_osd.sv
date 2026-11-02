`timescale 1ns/1ps
module tb_photo_status_osd;
    reg clk=0,mem_clk=0,rst_n=0;
    always #20 clk=~clk;always #4 mem_clk=~mem_clk;
    reg vs=1,de=0,menu=0,mute=0,notice=0,manual=0,pause=0,commit=0;
    reg [1:0] scene=0;
    reg [3:0] index=1;
    reg [11:0] active_source_width=1920,active_source_height=1080;
    reg resolution_notice=0,tick_1ms=0,underflow=0;
    reg started=0,running=0,finished=0;
    wire [23:0] rgb;
    wire active;
    reg [15:0] font[0:2047];
    integer legend_glyph[0:17];
    integer result_file,muted_pixels=0,auto_pixels=0,instruction_pixels=0,arc_pixels=0,manual_pixels=0;
    integer legend_pixels=0,resolution_yellow_pixels=0,resolution_black_pixels=0;
    wire [11:0] visible_source_width,visible_source_height;
    photo_badge_overlay #(.interaction_osd(1)) dut(
        .mem_clk(mem_clk),.mem_rst_n(rst_n),.clk(clk),.rst_n(rst_n),.vs(vs),.de(de),.rgb_in(24'habcdef),
        .frame_sync(vs),.frame_commit(commit),.active_index(index),
        .active_source_width(active_source_width),.active_source_height(active_source_height),
        .video_visible(1'b1),.underflow_flag(underflow),
        .menu_active(menu),.menu_item(3'd0),.music_mute(mute),.auto_notice(notice),.manual_notice(manual),.manual_pause(pause),
        .resolution_notice(resolution_notice),.tick_1ms(tick_1ms),
        .music_volume(3'd4),.brightness_level(3'd4),.eye_mode(2'd0),.transition_mode(2'd0),
        .transition_alpha(8'hff),.transition_wipe_active(1'b0),.transition_wipe_ramp(5'd0),
        .slideshow_seconds(5'd5),.scene_mode(scene),.exam_started(started),.exam_running(running),
        .exam_finished(finished),.exam_duration_index(3'd0),.exam_minutes(8'd30),.exam_second(6'd0),
        .subtitle_enable(1'b0),.subtitle_ready(1'b0),.subtitle_speed(3'd2),.subtitle_alpha(3'd1),
        .subtitle_notice_length(5'd0),.subtitle_teacher_length(5'd0),.subtitle_mem_en(1'b0),
        .subtitle_mem_write_en(1'b0),.subtitle_mem_addr(11'd0),.subtitle_mem_write_data(16'd0),
        .subtitle_mem_read_data(),.rgb_out(rgb),.overlay_active(active),.frame_start_out(),
        .visible_index_out(),.visible_valid_out(),.incoming_valid_out(),.incoming_index_out(),
        .visible_source_width_out(visible_source_width),.visible_source_height_out(visible_source_height),
        .scene_visible_out(),.visible_frame_pulse_out());
    task boundary;begin
        @(negedge clk);vs=0;de=0;repeat(5)@(negedge clk);vs=1;repeat(5)@(negedge clk);
    end endtask
    task settle;begin repeat(3)begin repeat(100)@(negedge clk);boundary();end end endtask
    task pulse_commit;begin @(negedge mem_clk);commit=1;@(negedge mem_clk);commit=0;repeat(10)@(negedge clk);end endtask
    task milliseconds(input integer count);
        repeat(count)begin
            @(negedge mem_clk);tick_1ms=1;@(negedge mem_clk);tick_1ms=0;
            repeat(8)@(negedge clk);
        end
    endtask
    task resolution_event;
        begin
            @(negedge mem_clk);resolution_notice=1;@(negedge mem_clk);resolution_notice=0;
            repeat(30)@(negedge clk);
        end
    endtask
    task raster(input integer mode);
        integer x,y,glyph,pos,row,word_id,cell_id,mapword,fd;
        reg expected_bit;reg [23:0] expected_color;
        begin
            fd=$fopen(mode==0 ? "work/badge_mute.ppm" : mode==1 ? "work/badge_mute_menu.ppm" : mode==2 ? "work/badge_exam_controls.ppm" : mode==3 ? "work/badge_manual.ppm" : mode==5 ? "work/badge_resolution.ppm" : "work/badge_unmute.ppm","w");
            $fwrite(fd,"P3\n640 480\n255\n");boundary();
            for(y=0;y<480;y=y+1)begin
                for(x=0;x<640;x=x+1)begin
                    @(negedge clk);de=1;#1;
                    $fwrite(fd,"%0d %0d %0d\n",rgb[23:16],rgb[15:8],rgb[7:0]);
                    if(dut.pixel_x!=x || dut.pixel_y!=y)$fatal(1,"OSD changed coordinate phase %d/%d %d/%d",dut.pixel_x,x,dut.pixel_y,y);
                    if(x==600 && ((mode==0 && y==20)||(mode==1 && y==220)))begin
                        if(rgb!=0)$fatal(1,"mute background not black %h",rgb);muted_pixels=muted_pixels+1;
                    end
                    if(mode==1 && y>=172 && y<204 && ((x>=408 && x<488)||(x>=504 && x<584)) && rgb==24'heef3f5)
                        legend_pixels=legend_pixels+1;
                    if(mode==1 && y>=172 && y<188 && ((x>=408 && x<488)||(x>=504 && x<584)))begin
                        pos=x<488 ? x-408 : x-504;cell_id=pos/16+(x<488 ? 0 : 5);
                        expected_bit=font[legend_glyph[cell_id]*16+y-172][15-pos%16];
                        if(rgb!==(expected_bit ? 24'heef3f5 : 24'h111820))
                            $fatal(1,"K1/K2 legend glyph mismatch x=%0d y=%0d",x,y);
                    end
                    if(mode==1 && y>=188 && y<204 && ((x>=416 && x<480)||(x>=520 && x<584)))begin
                        pos=x<480 ? x-416 : x-520;cell_id=pos/16+(x<480 ? 10 : 14);
                        expected_bit=font[legend_glyph[cell_id]*16+y-188][15-pos%16];
                        if(rgb!==(expected_bit ? 24'heef3f5 : 24'h111820))
                            $fatal(1,"K3/K4 legend glyph mismatch x=%0d y=%0d",x,y);
                    end
                    if(mode==5 && x>=472 && x<616 && y>=24 && y<40 && rgb==24'hfff080)
                        resolution_yellow_pixels=resolution_yellow_pixels+1;
                    if(mode==5 && x>=472 && x<616 && y>=24 && y<40 && rgb==24'h000000)
                        resolution_black_pixels=resolution_black_pixels+1;
                    if((mode==5 || mode==6) && x>=(mode==5 ? 472 : 360) &&
                        x<(mode==5 ? 616 : 504) && y>=24 && y<40)begin
                        pos=x-(mode==5 ? 472 : 360);cell_id=pos/16;
                        case(cell_id)
                            0:glyph=45;1:glyph=53;2:glyph=46;3:glyph=44;4:glyph=91;
                            5:glyph=45;6:glyph=44;7:glyph=52;default:glyph=44;
                        endcase
                        expected_bit=font[glyph*16+y-24][15-pos%16];
                        if(rgb!==(expected_bit ? 24'hfff080 : 24'd0))
                            $fatal(1,"resolution glyph mismatch x=%0d y=%0d got=%h",x,y,rgb);
                    end
                    if(mode==0 && x>=556 && x<588 && y>=28 && y<44)begin
                        mapword=font[1472+25*4];glyph=x<572 ? mapword&127 : (mapword>>7)&127;
                        expected_bit=(font[glyph*16+y-28]>>(15-((x-556)%16)))&1;
                        expected_color=expected_bit ? 24'heef3f5 : 24'd0;
                        if(rgb!==expected_color)$fatal(1,"mute glyph %d,%d expected=%h got=%h",x,y,expected_color,rgb);
                    end
                    if(mode==0 && x>=472 && x<504 && y>=24 && y<40)begin
                        mapword=font[1472+26*4];glyph=x<488 ? mapword&127 : (mapword>>7)&127;
                        expected_bit=(font[glyph*16+y-24]>>(15-((x-472)%16)))&1;
                        if(rgb!==(expected_bit ? 24'heef3f5 : 24'd0))$fatal(1,"auto glyph pixel");auto_pixels=auto_pixels+1;
                    end
                    if(mode==2 && x>=184 && x<248 && y>=336 && y<352)begin
                        cell_id=(x-184)/16;word_id=27;mapword=font[1472+word_id*4+cell_id/2];
                        glyph=(mapword>>(7*(cell_id%2)))&127;
                        expected_bit=(font[glyph*16+y-336]>>(15-((x-184)%16)))&1;
                        if(expected_bit && rgb!==24'heef3f5)$fatal(1,"exam instruction pixel");instruction_pixels=instruction_pixels+1;
                    end
                    if(mode==3 && x>=464 && x<616 && y>=16 && y<48 && rgb==24'heef3f5)manual_pixels=manual_pixels+1;
                    if(mode==4 && x>=544 && x<568 && y>=20 && y<42 && rgb==24'heef3f5)arc_pixels=arc_pixels+1;
                end
                @(negedge clk);de=0;repeat(8)@(negedge clk);
            end
            $fclose(fd);
        end
    endtask
    initial begin
        legend_glyph[0]=75;legend_glyph[1]=45;legend_glyph[2]=83;legend_glyph[3]=84;legend_glyph[4]=85;
        legend_glyph[5]=75;legend_glyph[6]=46;legend_glyph[7]=86;legend_glyph[8]=84;legend_glyph[9]=85;
        legend_glyph[10]=75;legend_glyph[11]=47;legend_glyph[12]=87;legend_glyph[13]=88;
        legend_glyph[14]=75;legend_glyph[15]=48;legend_glyph[16]=89;legend_glyph[17]=90;
        result_file=$fopen("tb_photo_status_osd.result","w");$readmemh("photo_font.dath",font);
        if(font[75*16]!==16'd0 || font[75*16+15]!==16'd0 ||
            font[75*16+1]!==16'h1818 || font[75*16+7]!==16'h1e00 ||
            font[75*16+14]!==16'h1818)
            $fatal(1,"K key-label glyph must use the same 10x14 pixel grid as the digits");
        if(font[1472+32*4]!==16'h2552)$fatal(1,"manual word map missing");
        repeat(10)@(negedge clk);rst_n=1;mute=1;pulse_commit();settle();
        @(negedge mem_clk);notice=1;@(negedge mem_clk);notice=0;
        boundary();repeat(10)@(negedge clk);raster(0);
        milliseconds(2000);if(!dut.mute_box)$fatal(1,"K1 millisecond ticks changed the original mute frame timer");
        repeat(90)boundary();if(dut.mute_box)$fatal(1,"mute badge stayed visible after 90 frames");
        menu=1;mute=0;settle();
        mute=1;pulse_commit();settle();raster(1);
        repeat(90)boundary();
        menu=0;mute=0;pulse_commit();
        wait(dut.config_hold[49:49] == 1'b0);
        wait(dut.config_ready);
        boundary();
        raster(4);
        menu=0;mute=0;pause=1;manual=1;@(negedge mem_clk);manual=0;settle();
        if(!dut.manual_box)$fatal(1,"manual action did not select manual popup");
        raster(3);
        repeat(60)boundary();if(dut.manual_box)$fatal(1,"manual popup did not expire after 60 frames");
        pause=0;scene=1;index=8;pulse_commit();settle();
        @(negedge clk);de=1;repeat(6)@(negedge clk);de=0;settle();raster(2);
        scene=0;settle();pulse_commit();raster(4);
        @(negedge mem_clk);notice=1;@(negedge mem_clk);notice=0;
        repeat(10)@(negedge clk);boundary();
        repeat(60)boundary();if(dut.notice_frames!=0)$fatal(1,"auto popup did not expire after 60 frames");
        index=1;active_source_width=1920;active_source_height=1080;pulse_commit();raster(4);
        resolution_event();
        if(dut.resolution_ms!=2000)$fatal(1,"resolution prompt did not start its 2000-ms timer");
        raster(5);
        if(visible_source_width!=1920 || visible_source_height!=1080)$fatal(1,"OSD did not return visible-image source metadata");
        if(dut.resolution_ms!=2000 || resolution_yellow_pixels==0 || resolution_black_pixels==0)
            $fatal(1,"resolution toast layout/color/initial duration yellow=%0d black=%0d frames=%0d",
                resolution_yellow_pixels,resolution_black_pixels,dut.resolution_ms);
        mute=1;settle();resolution_event();
        if(!dut.sound_box || dut.resolution_x!=352)$fatal(1,"resolution did not avoid the sound popup");
        raster(6);mute=0;settle();milliseconds(2000);resolution_event();
        @(negedge mem_clk);manual=1;@(negedge mem_clk);manual=0;repeat(10)@(negedge clk);
        if(!dut.manual_box || dut.resolution_box)$fatal(1,"manual event did not replace resolution notice");
        for(integer event_delay=0;event_delay<20;event_delay=event_delay+1)begin
            @(negedge mem_clk);resolution_notice=1;@(negedge mem_clk);resolution_notice=0;
            repeat(event_delay)@(negedge clk);
            @(negedge mem_clk);manual=1;@(negedge mem_clk);manual=0;
            repeat(32)@(negedge clk);
            if(!dut.manual_box || dut.resolution_box)
                $fatal(1,"later manual action lost to K1 conversion at delay=%0d",event_delay);
        end
        resolution_event();
        active_source_width=320;active_source_height=240;
        resolution_event();
        if(dut.resolution_width_frame!==16'h1920 || dut.resolution_height_frame!==16'h1080)
            $fatal(1,"background dimensions replaced the visible image dimensions");
        milliseconds(1999);
        if(!dut.resolution_box || dut.resolution_ms!=1)$fatal(1,"resolution toast expired before 2000 ms");
        resolution_event();
        if(dut.resolution_ms!=2000)$fatal(1,"repeated K1 did not refresh the resolution notice");
        milliseconds(2000);
        if(dut.resolution_ms!=0 || dut.resolution_box)$fatal(1,"resolution toast did not expire after 2000 ms");
        resolution_event();index=2;pulse_commit();boundary();
        @(negedge clk);de=1;repeat(8)@(negedge clk);de=0;
        if(dut.resolution_box || dut.resolution_ms!=0)$fatal(1,"image commit retained a stale resolution toast");
        resolution_event();
        if(dut.resolution_width_frame!==16'h0320 || dut.resolution_height_frame!==16'h0240)
            $fatal(1,"new visible metadata did not replace old dimensions");
        scene=1;settle();resolution_event();
        if(dut.resolution_box || dut.resolution_ms!=0)$fatal(1,"exam scene leaked a resolution toast");
        scene=2;settle();resolution_event();
        if(dut.resolution_box || dut.resolution_ms!=0)$fatal(1,"fire scene leaked a resolution toast");
        scene=0;menu=1;settle();resolution_event();
        if(dut.resolution_box || dut.resolution_ms!=0)$fatal(1,"menu leaked a resolution toast");
        menu=0;settle();index=3;active_source_width=0;active_source_height=0;pulse_commit();boundary();
        @(negedge clk);de=1;repeat(8)@(negedge clk);de=0;resolution_event();
        if(dut.resolution_box)$fatal(1,"invalid dimensions opened a resolution toast");
        if(muted_pixels!=2 || auto_pixels!=512 || instruction_pixels!=1024 || arc_pixels==0 || manual_pixels==0 || legend_pixels==0)
            $fatal(1,"OSD incomplete coverage mute=%0d auto=%0d instruction=%0d arcs=%0d manual=%0d keys=%0d",
                muted_pixels,auto_pixels,instruction_pixels,arc_pixels,manual_pixels,legend_pixels);
        $fdisplay(result_file,"PASS K1 resolution uses 2000-ms expiry; original mute/auto/manual frame timers retained");
        $fdisplay(result_file,"PASS later manual action wins across 20 K1 conversion/event offsets");
        $fdisplay(result_file,"PASS native-font K1-K4 menu legend, yellow 1920x1080 resolution digits and 2000-ms expiry");
        $fdisplay(result_file,"PASS exam ready instructions and original RGB coordinate phase; no loading/pause countdown overlays");
        $fdisplay(result_file,"PASS tb_photo_status_osd");$fclose(result_file);$finish;
    end
endmodule
