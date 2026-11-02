`timescale 1ns/1ps
module tb_photo_overlay;
    reg mem_clk=0,clk=0,mem_rst_n=0,rst_n=0;
    always #4 mem_clk=~mem_clk;
    always #20 clk=~clk;
    reg vs=1,frame_sync=1,de=0,frame_commit=0;
    reg [23:0] rgb_in=24'h81c3ff;
    reg [3:0] active_index=0;
    reg video_visible=1,underflow_flag=0,menu_active=0;
    reg [2:0] menu_item=0;
    reg [1:0] scene_mode=0,eye_mode=0,transition_mode=0;
    reg [7:0] transition_alpha=8'hff;
    reg transition_wipe_active=0;
    reg [4:0] transition_wipe_ramp=0;
    reg [2:0] subtitle_speed=2,subtitle_alpha=1;
    reg [2:0] music_volume=4,brightness_level=4,exam_duration_index=0;
    reg [4:0] slideshow_seconds=5;
    reg exam_started=0,exam_running=0,exam_finished=0;
    reg [7:0] exam_minutes=30;
    reg [5:0] exam_second=0;
    wire [23:0] rgb_out;
    wire overlay_active;
    wire frame_start_out,visible_valid_out;
    wire [3:0] visible_index_out;
    integer result_file,image_file,bmp_file,read_count;
    integer level,value,eye,selected,mode_value,alpha_step;
    reg [7:0] bmp_data[0:921653];
    reg [15:0] font_expected[0:2047];
    reg [10:0] font_address=0;
    reg font_enable=0;
    wire [15:0] font_value;
    wire [15:0] map_value;
    photo_font_rom font_check_proc(.clk(clk),.enable(font_enable),
        .address(font_address),.row_data(font_value),
        .map_enable(font_enable),.map_address(11'd2047-font_address),.map_data(map_value));
    reg [23:0] source_pixel,expected_pixel;
    reg [48:0] held_before;
    photo_badge_overlay dut(
        .mem_clk(mem_clk),.mem_rst_n(mem_rst_n),.clk(clk),.rst_n(rst_n),
        .vs(vs),.de(de),.rgb_in(rgb_in),.frame_sync(frame_sync),
        .frame_commit(frame_commit),.active_index(active_index),
        .video_visible(video_visible),.underflow_flag(underflow_flag),
        .menu_active(menu_active),.menu_item(menu_item),.music_volume(music_volume),
        .manual_notice(1'b0),
        .brightness_level(brightness_level),.slideshow_seconds(slideshow_seconds),
        .eye_mode(eye_mode),.transition_mode(transition_mode),
        .subtitle_enable(1'b0),.subtitle_speed(subtitle_speed),.subtitle_alpha(subtitle_alpha),.subtitle_ready(1'b0),.subtitle_notice_length(5'd0),
        .subtitle_teacher_length(5'd0),.subtitle_mem_en(1'b0),.subtitle_mem_write_en(1'b0),.subtitle_mem_addr(11'd0),
        .subtitle_mem_write_data(16'd0),.subtitle_mem_read_data(),
        .transition_alpha(transition_alpha),.transition_wipe_active(transition_wipe_active),
        .transition_wipe_ramp(transition_wipe_ramp),.exam_duration_index(exam_duration_index),
        .scene_mode(scene_mode),.exam_started(exam_started),.exam_running(exam_running),
        .exam_finished(exam_finished),.exam_minutes(exam_minutes),.exam_second(exam_second),
        .rgb_out(rgb_out),.overlay_active(overlay_active),.frame_start_out(frame_start_out),
        .visible_index_out(visible_index_out),.visible_valid_out(visible_valid_out));
    task pixel_proc(input bit enabled,input [23:0] color);
        begin @(posedge clk);de<=enabled;rgb_in<=color;#1;end
    endtask
    task boundary_proc;
        begin
            @(negedge clk);vs=0;frame_sync=0;
            repeat(4)pixel_proc(0,0);
            @(negedge clk);vs=1;frame_sync=1;
            repeat(4)pixel_proc(0,0);
        end
    endtask
    task settle_proc;
        repeat(3)begin repeat(100)pixel_proc(0,0);boundary_proc();end
    endtask
    task commit_proc(input [3:0] index);
        begin
            @(negedge mem_clk);active_index=index;frame_commit=1;
            @(negedge mem_clk);frame_commit=0;
            repeat(6)@(negedge clk);
        end
    endtask
    function [23:0] adjust_expected(input [23:0] color,input integer scale,input integer mode);
        integer r,g,b;
        begin
            r=transition_alpha==8'hff ? color[23:16] : (color[23:16]*transition_alpha)/256;
            g=transition_alpha==8'hff ? color[15:8] : (color[15:8]*transition_alpha)/256;
            b=transition_alpha==8'hff ? color[7:0] : (color[7:0]*transition_alpha)/256;
            r=(r*scale)/4;g=(g*scale)/4;b=(b*scale)/4;
            if(mode==1)b=b*3/4;
            else if(mode==2)b=b/2;
            adjust_expected={8'(r),8'(g),8'(b)};
        end
    endfunction
    function integer label_glyph(input integer item,input integer glyph_cell);
        case(item)
            0:label_glyph=glyph_cell==0 ? 3:4;
            1:label_glyph=glyph_cell==0 ? 5:6;
            2:label_glyph=glyph_cell==0 ? 7:8;
            3:label_glyph=glyph_cell==0 ? 9:10;
            4:label_glyph=glyph_cell==0 ? 57:58;
            5:label_glyph=glyph_cell==0 ? 66:67;
            6:label_glyph=glyph_cell==0 ? 66:12;
            default:label_glyph=glyph_cell==0 ? 70:71;
        endcase
    endfunction
    task load_photo(input integer index);
        begin
            bmp_file=$fopen($sformatf("tf_card/PIC%0d.BMP",index),"rb");
            if(!bmp_file)$fatal(1,"photo missing");
            read_count=$fread(bmp_data,bmp_file);$fclose(bmp_file);
            if(read_count!=921654)$fatal(1,"photo fixture size");
        end
    endtask
    task raster_proc(input integer chosen,input string filename,input bit expect_scene);
        integer px,py,pos,hits,slot,item,glyph,glyph_cell,cell_index,grow,gcol,start_row,green_hits;
        reg [23:0] color,expected,label_color;
        reg bit_value;
        begin
            boundary_proc();
            image_file=$fopen(filename,"wb");if(!image_file)$fatal(1,"raster create");
            $fwrite(image_file,"P6\n640 480\n255\n");hits=0;green_hits=0;
            for(py=0;py<480;py=py+1)begin
                for(px=0;px<640;px=px+1)begin
                    pos=54+(479-py)*1920+px*3;color={bmp_data[pos+2],bmp_data[pos+1],bmp_data[pos]};
                    pixel_proc(1,color);
                    if(dut.pixel_x!=px || dut.pixel_y!=py)$fatal(1,"coordinate mismatch");
                    $fwrite(image_file,"%c%c%c",rgb_out[23:16],rgb_out[15:8],rgb_out[7:0]);
                    if(overlay_active)hits=hits+1;
                    else if(rgb_out!==adjust_expected(color,brightness_level,eye_mode))
                        $fatal(1,"background color/latency x=%0d y=%0d",px,py);
                    if(chosen>=0)begin
                        start_row=chosen>2 ? chosen-2:0;
                        if(px>=384 && px<416 && ((py>=64 && py<80)||(py>=100 && py<116)||(py>=136 && py<152)))begin
                            slot=py<80 ? 0:py<116 ? 1:2;item=start_row+slot;
                            grow=py-(64+36*slot);gcol=(px-384)%16;glyph_cell=(px-384)/16;
                            glyph=label_glyph(item,glyph_cell);
                            bit_value=font_expected[glyph*16+grow][15-gcol];
                            label_color=item==chosen ? 24'hfff080:24'heef3f5;
                            expected=bit_value ? label_color:item==chosen ? 24'h263a4b:24'h111820;
                            if(rgb_out!==expected)$fatal(1,"Chinese glyph alignment item=%0d x=%0d y=%0d got=%h exp=%h",item,px,py,rgb_out,expected);
                        end
                        if(chosen==4 && item==4 && px>=544 && px<608 && py>=136 && py<152)begin
                            cell_index=(px-544)/16;grow=py-136;gcol=(px-544)%16;glyph=0;
                            case(transition_mode)
                                0:if(cell_index==1 || cell_index==2)glyph=cell_index==1 ? 13:14;
                                1:case(cell_index)0:glyph=59;1:glyph=60;2:glyph=59;3:glyph=61;endcase
                                default:case(cell_index)0:glyph=62;1:glyph=63;2:glyph=64;3:glyph=65;endcase
                            endcase
                            bit_value=font_expected[glyph*16+grow][15-gcol];
                            expected=bit_value ? 24'hfff080 : 24'h263a4b;
                            if(rgb_out!==expected)$fatal(1,"transition value glyph mode=%0d cell=%0d x=%0d",transition_mode,cell_index,px);
                        end
                        if(rgb_out==24'hfff080 && py>=56 && py<164 &&
                            (py<64+(chosen-start_row)*36 || py>=80+(chosen-start_row)*36))
                            $fatal(1,"highlight leaked into other rows");
                    end
                    if(expect_scene && scene_mode==2 && px>=256 && px<384 && py>=128 && py<160)begin
                        cell_index=(px-256)/32;grow=(py-128)/2;gcol=((px-256)%32)/2;
                        case(cell_index)0:glyph=34;1:glyph=35;2:glyph=24;default:glyph=25;endcase
                        bit_value=font_expected[glyph*16+grow][15-gcol];
                        expected=adjust_expected(color,brightness_level,eye_mode);
                        expected={8'(46+(expected[23:16]>>4)),8'(24+(expected[15:8]>>4)),
                            8'(24+(expected[7:0]>>4))};
                        if(bit_value)expected=dut.blink_on ? 24'hffdfce : 24'h633c32;
                        if(rgb_out!==expected)$fatal(1,"emergency title pixel x=%0d y=%0d",px,py);
                    end
                    if(rgb_out==24'h40ff80 || rgb_out==24'h164e2a)green_hits=green_hits+1;
                end
                repeat(4)pixel_proc(0,0);
            end
            $fclose(image_file);
            if(chosen>=0 && hits!=256*192)$fatal(1,"menu dimensions/opacity");
            if(chosen<0 && ((hits!=0)!=expect_scene))$fatal(1,"scene visibility expected=%b hits=%0d",expect_scene,hits);
            if(expect_scene && scene_mode==2 && green_hits<3000)$fatal(1,"green arrow missing");
        end
    endtask
    initial begin #500000000;$fatal(1,"overlay timeout");end
    initial begin
        result_file=$fopen("tb_photo_overlay.result","w");
        $readmemh("photo_font.dath",font_expected);
        if(font_expected[1472+16*4]!=={2'd0,7'd35,7'd34} ||
            font_expected[1472+16*4+1]!=={2'd0,7'd25,7'd24})
            $fatal(1,"emergency title must map to ying/ji/mo/shi in the existing four cells");
        for(selected=0;selected<2048;selected=selected+1)begin
            @(negedge clk);font_address=selected;font_enable=1;
            @(posedge clk);#1;
            if(font_value!==font_expected[selected])$fatal(1,"native BRAM glyph address %0d",selected);
            if(map_value!==font_expected[2047-selected])$fatal(1,"native BRAM map port address %0d",2047-selected);
        end
        @(negedge clk);font_enable=0;font_address=0;
        repeat(3)@(posedge clk);
        if(font_value!==font_expected[2047])$fatal(1,"BRAM disabled output did not hold");
        $fdisplay(result_file,"PASS all 2048 native BRAM font addresses, synchronous read and disabled hold");
        repeat(5)@(negedge clk);mem_rst_n=1;rst_n=1;settle_proc();
        for(eye=0;eye<3;eye=eye+1)for(level=0;level<5;level=level+1)begin
            @(negedge mem_clk);brightness_level=level;eye_mode=eye;settle_proc();
            for(value=0;value<256;value=value+1)begin
                source_pixel={8'(value),8'(255-value),8'(value^85)};
                pixel_proc(1,source_pixel);expected_pixel=adjust_expected(source_pixel,level,eye);
                if(rgb_out!==expected_pixel || overlay_active)$fatal(1,"brightness/eye mismatch");
            end
            pixel_proc(0,0);
        end
        $fdisplay(result_file,"PASS 256 channel values x five brightness x three eye modes, OFF exact, no RGB delay");
        @(negedge mem_clk);brightness_level=4;eye_mode=0;settle_proc();
        for(alpha_step=0;alpha_step<=16;alpha_step=alpha_step+1)begin
            transition_alpha=alpha_step==16 ? 255:alpha_step*16;
            for(value=0;value<256;value=value+1)begin
                source_pixel={8'(value),8'(255-value),8'(value^85)};
                pixel_proc(1,source_pixel);
                if(rgb_out!==adjust_expected(source_pixel,4,0))$fatal(1,"fade sample alpha=%0d value=%0d",transition_alpha,value);
            end
            pixel_proc(0,0);
        end
        transition_alpha=255;
        $fdisplay(result_file,"PASS all 256 channel values at 17 transition levels; exact bypass/black endpoints and zero added RGB delay");
        @(negedge mem_clk);menu_active=1;music_volume=4;brightness_level=4;eye_mode=0;
        slideshow_seconds=30;exam_minutes=180;exam_second=59;exam_duration_index=5;
        wait(dut.config_ready);held_before=dut.config_hold;
        @(negedge mem_clk);menu_item=7;transition_mode=2;music_volume=2;brightness_level=1;eye_mode=2;subtitle_speed=4;subtitle_alpha=3;
        slideshow_seconds=1;exam_minutes=120;exam_second=7;
        repeat(90)@(negedge clk);
        if(dut.config_hold!==held_before || dut.menu_frame)$fatal(1,"unacknowledged mailbox changed");
        boundary_proc();
        if(!dut.menu_frame || dut.volume_frame!=4 || dut.minutes_frame!=12'h180 ||
            dut.seconds_frame!=8'h59 || dut.eye_frame!=0)$fatal(1,"first atomic snapshot");
        settle_proc();
        if(dut.menu_item_frame!=7 || dut.transition_mode_frame!=2 || dut.volume_frame!=2 || dut.eye_frame!=2 || dut.subtitle_speed_frame!=4 || dut.subtitle_alpha_frame!=3 ||
            dut.minutes_frame!=12'h120 || dut.seconds_frame!=8'h07)$fatal(1,"busy latest snapshot lost");
        $fdisplay(result_file,"PASS held CDC mailbox, frame-only adoption, latest update and three-digit minutes");
        load_photo(2);
        @(negedge mem_clk);music_volume=4;brightness_level=4;eye_mode=0;subtitle_speed=2;subtitle_alpha=1;slideshow_seconds=30;
        for(selected=0;selected<8;selected=selected+1)begin
            @(negedge mem_clk);menu_item=selected;transition_mode=selected==4 ? 2 : 0;
            transition_alpha=selected==4 ? 0 : 8'hff;settle_proc();
            raster_proc(selected,$sformatf("work/chinese_menu_%0d.ppm",selected),0);
        end
        for(mode_value=0;mode_value<2;mode_value=mode_value+1)begin
            @(negedge mem_clk);menu_item=4;transition_mode=mode_value;transition_alpha=0;settle_proc();
            raster_proc(4,$sformatf("work/chinese_menu_transition_%0d.ppm",mode_value),0);
        end
        @(negedge mem_clk);transition_alpha=8'hff;settle_proc();
        $fdisplay(result_file,"PASS eight complete Chinese menu rasters: exact glyph pixels, subtitle/transition labels, rolling three-row window, highlights and bounds");
        @(negedge mem_clk);menu_active=0;scene_mode=1;exam_minutes=180;exam_second=0;
        exam_duration_index=5;settle_proc();load_photo(9);
        commit_proc(0);raster_proc(-1,"work/chinese_scene_hidden.ppm",0);
        video_visible=0;commit_proc(8);raster_proc(-1,"work/chinese_scene_not_ready.ppm",0);
        video_visible=1;raster_proc(-1,"work/chinese_exam_180.ppm",1);
        if(dut.minutes_frame!=12'h180 || dut.progress_frame!=240)$fatal(1,"180 minute/progress initial");
        @(negedge mem_clk);exam_started=1;exam_running=1;exam_minutes=5;exam_second=0;
        settle_proc();if(dut.timer_color!=24'hffbd70)$fatal(1,"5 minute threshold");
        raster_proc(-1,"work/chinese_exam_warning.ppm",1);
        @(negedge mem_clk);exam_minutes=1;settle_proc();
        if(dut.timer_color!=24'hff8278)$fatal(1,"1 minute threshold");
        @(negedge mem_clk);exam_running=0;settle_proc();
        if(dut.status_color!=24'hfff080)$fatal(1,"paused color");
        @(negedge mem_clk);exam_finished=1;exam_minutes=0;settle_proc();
        if(dut.progress_frame!=0)$fatal(1,"finished progress");
        $fdisplay(result_file,"PASS centered 180:00, progress endpoints and warning/urgent/pause/finished colors");
        @(negedge mem_clk);exam_duration_index=6;exam_minutes=1;exam_second=0;
        exam_started=0;exam_running=0;exam_finished=0;settle_proc();
        if(dut.minutes_frame!=12'h001 || dut.seconds_frame!=0 || dut.progress_frame!=240 ||
            dut.status_color!=24'h9ddce4)$fatal(1,"demo 01:00 ready display/progress");
        raster_proc(-1,"work/chinese_exam_demo_01.ppm",1);
        @(negedge mem_clk);exam_started=1;exam_running=1;exam_minutes=0;
        for(selected=59;selected>=0;selected=selected-1)begin
            @(negedge mem_clk);exam_second=selected;exam_finished=selected==0;
            exam_running=selected!=0;settle_proc();
            if(dut.seconds_frame!=={4'(selected/10),4'(selected%10)} ||
                dut.progress_frame!=(selected/2)*8 || dut.timer_color!=24'hff8278)
                $fatal(1,"demo second/progress/color at %0d seconds",selected);
        end
        $fdisplay(result_file,"PASS demo 01:00 raster and all 60 remaining-second values: BCD, two-second progress steps and urgent/end colors");
        @(negedge mem_clk);scene_mode=2;settle_proc();load_photo(10);
        raster_proc(-1,"work/chinese_fire_wrong_image.ppm",0);
        underflow_flag=1;commit_proc(9);raster_proc(-1,"work/chinese_fire_underflow.ppm",0);
        underflow_flag=0;raster_proc(-1,"work/chinese_fire.ppm",1);
        while(dut.blink_tick!=0)boundary_proc();
        for(selected=0;selected<60;selected=selected+1)begin
            if(dut.blink_on!==(selected<30))$fatal(1,"standard blink phase %0d",selected);
            boundary_proc();
        end
        if(dut.blink_tick!=0)$fatal(1,"blink counter wrap");
        $fdisplay(result_file,"PASS PIC9/PIC10 commit and valid-DE gating, underflow suppression, green fire arrow and bounded blink");
        $fdisplay(result_file,"PASS ying/ji/mo/shi emergency title: original four 32x32 cells, exact raster pixels");
        $fdisplay(result_file,"PASS tb_photo_overlay");$fclose(result_file);$finish;
    end
endmodule
